#!/usr/bin/env ruby

require "selenium-webdriver"
require "json"
require "fileutils"
require "net/http"
require "socket"
require "timeout"

ROOT = File.expand_path("../../../../", __dir__)
RUNS_DIR = File.join(ROOT, "tmp/verify-reactionview")

COUNTER_JS = <<~'JS'
  (() => {
    window.__verifySlots = [];
    const record = (url) => {
      const text = String(url);
      if (text.includes("format=slots")) window.__verifySlots.push(text);
    };
    const originalFetch = window.fetch;
    window.fetch = function(input) {
      record(typeof input === "string" ? input : input.url);
      return originalFetch.apply(this, arguments);
    };
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      record(url);
      return originalOpen.apply(this, arguments);
    };
  })();
JS

FEATURES = %w[sprint-hub-search sprint-hub-row-state settings-tabs sprint-hub-add].freeze

class VerificationFailure < StandardError; end

class Verifier
  def initialize(features:, port:, keep:)
    @features = features
    @requested_port = port
    @keep = keep
    @results = []
    @run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{Process.pid}"
    @run_dir = File.join(RUNS_DIR, @run_id)
    @db_path = File.join(@run_dir, "verify.sqlite3")
    @server_log = File.join(@run_dir, "server.log")
    @base_url = nil
    @server_pid = nil
    @driver = nil
  end

  def run
    FileUtils.mkdir_p(@run_dir)
    puts "evidence: #{@run_dir}"
    prepare_database
    start_server
    start_browser
    @features.each { |feature| run_feature(feature) }
    write_result
    puts JSON.pretty_generate(@results)
    exit(@results.all? { |r| r["status"] == "VERIFIED" } ? 0 : 1)
  ensure
    @driver&.quit
    stop_server
    remove_database unless @keep
  end

  private

  def prepare_database
    log = File.join(@run_dir, "database.log")
    env = { "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{@db_path}" }
    FileUtils.rm_f(Dir.glob("#{@db_path}*"))
    run_command!(env, "bin/rails", "db:prepare", log)
    run_command!(env, "bin/rails", "db:seed:replant", log)
    run_command!(env, "bin/rails", "runner",
                 'puts "tasks=#{Task.count} proposals=#{Proposal.count} talks=#{Talk.count}"', log)
    counts = File.read(log)[/tasks=(\d+) proposals=(\d+) talks=(\d+)/]
    raise VerificationFailure, "seed counts missing from #{log}" unless counts
    raise VerificationFailure, "unexpected seed counts: #{counts}" unless counts == "tasks=10 proposals=3 talks=12"
  end

  def run_command!(env, *command, log)
    File.open(log, "a") do |file|
      return if system(env, *command, chdir: ROOT, out: file, err: file)
    end
    raise VerificationFailure, "#{command.join(" ")} failed; see #{log}"
  end

  def start_server
    port = free_port(@requested_port)
    @base_url = "http://127.0.0.1:#{port}"
    env = { "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{@db_path}" }
    @server_pid = Process.spawn(env, "bin/rails", "server", "-p", port.to_s, "-b", "127.0.0.1",
                                chdir: ROOT, out: @server_log, err: @server_log, pgroup: true)
    deadline = Time.now + 40
    until healthy?
      if Time.now > deadline
        raise VerificationFailure, "server did not become ready; see #{@server_log}\n#{log_tail}"
      end
      sleep 0.25
    end
    puts "server: #{@base_url}"
  end

  def healthy?
    Net::HTTP.start("127.0.0.1", URI(@base_url).port, open_timeout: 1, read_timeout: 1) do |http|
      http.get("/up").is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end

  def log_tail
    File.readlines(@server_log).last(20).join
  rescue StandardError
    ""
  end

  def free_port(preferred)
    (preferred...(preferred + 20)).each do |port|
      server = TCPServer.new("127.0.0.1", port)
      server.close
      return port
    rescue Errno::EADDRINUSE
      next
    end
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  def start_browser
    options = Selenium::WebDriver::Chrome::Options.new
    %w[
      --headless=new
      --no-sandbox
      --disable-dev-shm-usage
      --disable-gpu
      --window-size=1400,1400
    ].each { |argument| options.add_argument(argument) }
    @driver = Selenium::WebDriver.for(:chrome, options: options)
    @driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: COUNTER_JS)
    @wait = Selenium::WebDriver::Wait.new(timeout: 15, interval: 0.05)
  end

  def stop_server
    return unless @server_pid

    Process.kill("TERM", -@server_pid)
    Timeout.timeout(10) { Process.wait(@server_pid) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", -@server_pid) rescue nil
    Process.wait(@server_pid) rescue nil
  end

  def remove_database
    FileUtils.rm_f(Dir.glob("#{@db_path}*"))
  end

  def run_feature(feature)
    puts "\n== #{feature}"
    @current_evidence = []
    assertions = send(feature.tr("-", "_"))
    @results << {
      "feature" => feature,
      "status" => "VERIFIED",
      "assertions" => assertions,
      "slots" => slots_snapshot,
      "evidence" => evidence(feature)
    }
  rescue StandardError => error
    @results << {
      "feature" => feature,
      "status" => "NOT VERIFIED",
      "error" => "#{error.class}: #{error.message}",
      "slots" => safe_slots_snapshot,
      "evidence" => failure_evidence(feature)
    }
  end

  def sprint_hub_search
    visit("/")
    wait_rows(10)
    baseline = slots_count
    find(css: 'input[name="search"]').send_keys("quick start")
    wait_rows(1)
    @wait.until { find(css: ".toolbar-note").text.include?("の結果") }
    sleep 0.4

    assert(slots_count - baseline >= 1, "search should send at least one slots request")
    row = find(css: ".task-list .task-item").text
    assert(row.include?("Read the ReActionView quick start"), "search should show the matching row")
    ["query 'quick start' narrowed the list to one row", "search sent #{slots_count - baseline} slots request(s)"]
  end

  def sprint_hub_row_state
    visit("/")
    wait_rows(10)
    baseline = slots_count

    find(css: ".task-list .task-item .task-check").click
    @wait.until { find(css: ".task-stat").text.start_with?("1/10") }
    find(css: ".task-list .task-item .task-pin").click
    @wait.until { find(css: ".pin-stat").text.include?("1") }
    sleep 0.3

    assert(slots_count == baseline, "done and pin should stay client-side")
    ["done count moved to 1/10", "pin count moved to 1", "row state sent 0 slots requests"]
  end

  def settings_tabs
    visit("/settings")
    baseline = slots_count
    %w[Notifications Billing Profile].each do |tab|
      find(xpath: "//nav[contains(@class,'settings-nav')]//button[contains(., '#{tab}')]").click
      @wait.until { find(css: '.settings-nav button[aria-pressed="true"]').text == tab }
      visible = @driver.find_elements(css: ".settings-tab-panel").select(&:displayed?)
      assert(visible.size == 1, "#{tab} should show exactly one panel")
      screenshot("settings-tabs-#{tab.downcase}")
    end
    assert(slots_count == baseline, "tab switches should stay client-side")
    ["Notifications, Billing, and Profile each opened one panel", "tab switches sent 0 slots requests"]
  end

  def sprint_hub_add
    visit("/")
    wait_rows(10)
    search_baseline = slots_count
    find(css: 'input[name="search"]').send_keys("quick start")
    wait_rows(1)
    @wait.until { find(css: ".toolbar-note").text.include?("の結果") }
    search_delta = slots_count - search_baseline
    assert(search_delta >= 1, "search should send a slots request before add")

    drawer_baseline = slots_count
    find(xpath: "//button[contains(., '新規タスク')]").click
    @wait.until { @driver.find_elements(css: ".drawer").any? }
    drawer_delta = slots_count - drawer_baseline
    assert(drawer_delta >= 1, "opening the drawer should send a slots request")

    add_baseline = slots_count
    title = "verify probe #{@run_id}"
    hero_before_add = find(css: ".hero-badge").text
    find(css: "input#task_title").send_keys(title)
    button = find(xpath: "//aside[contains(@class,'drawer')]//button[contains(., '追加')]")
    @wait.until { button.enabled? }
    button.click

    optimistic_rows = nil
    optimistic_png = File.join(@run_dir, "sprint-hub-add-optimistic.png")
    @wait.until do
      optimistic_rows = row_texts
      next false unless optimistic_rows.size == 2

      @driver.save_screenshot(optimistic_png)
      true
    end
    hero_after_add = find(css: ".hero-badge").text
    optimistic = File.join(@run_dir, "sprint-hub-add-optimistic.json")
    File.write(optimistic, JSON.pretty_generate(
      "title" => title, "rows" => optimistic_rows,
      "hero_before_add" => hero_before_add, "hero_after_add" => hero_after_add
    ))
    @current_evidence << optimistic
    @current_evidence << optimistic_png

    add_delta = slots_count - add_baseline
    assert(add_delta >= 1, "add should send a slots request")
    assert(slots_urls.any? { |url| url.include?("/tasks") }, "add should POST to the tasks slots endpoint")
    assert(optimistic_rows.any? { |row| row.include?(title) }, "add should insert the new row optimistically")

    sync_baseline = slots_count
    find(xpath: "//button[contains(., '同期')]").click
    @wait.until { find(css: ".hero-badge").text.include?("11") }
    wait_rows(1)
    assert(slots_count - sync_baseline >= 1, "sync should send a slots request")
    [
      "search sent #{search_delta} slots request(s)",
      "opening the drawer sent #{drawer_delta} slots request(s)",
      "add sent #{add_delta} slots request(s) through the tasks endpoint",
      "the optimistic row appeared before sync; hero moved from #{hero_before_add.inspect} to #{hero_after_add.inspect}",
      "sync restored the filtered list and the hero reached 11"
    ]
  end

  def visit(path)
    @driver.navigate.to("#{@base_url}#{path}")
    @wait.until { @driver.execute_script("return document.readyState") == "complete" }
    sleep 0.8
  end

  def wait_rows(count)
    @wait.until { @driver.find_elements(css: ".task-list .task-item").size == count }
  end

  def row_texts
    @driver.execute_script(
      "return [...document.querySelectorAll('.task-list .task-item')].map((row) => row.innerText)"
    )
  end

  def find(css: nil, xpath: nil)
    css ? @driver.find_element(css: css) : @driver.find_element(xpath: xpath)
  end

  def slots_count
    @driver.execute_script("return window.__verifySlots.length")
  end

  def slots_urls
    @driver.execute_script("return window.__verifySlots")
  end

  def slots_snapshot
    { "count" => slots_count, "urls" => slots_urls }
  end

  def safe_slots_snapshot
    slots_snapshot
  rescue StandardError
    { "count" => nil, "urls" => [] }
  end

  def screenshot(name)
    path = File.join(@run_dir, "#{name}.png")
    @driver.save_screenshot(path)
    @current_evidence << path
    path
  end

  def evidence(feature)
    screenshot(feature)
    html = File.join(@run_dir, "#{feature}.html")
    File.write(html, @driver.page_source)
    @current_evidence << html
    @current_evidence.dup
  end

  def failure_evidence(feature)
    screenshot("#{feature}-failure")
    html = File.join(@run_dir, "#{feature}-failure.html")
    File.write(html, @driver.page_source)
    @current_evidence + [html]
  rescue StandardError
    @current_evidence.dup
  end

  def write_result
    File.write(File.join(@run_dir, "result.json"), JSON.pretty_generate(@results))
  end

  def assert(condition, message)
    raise VerificationFailure, message unless condition
  end
end

class Doctor
  def run
    puts "ruby: #{RUBY_VERSION}"
    puts "selenium: #{Selenium::WebDriver::VERSION}"
    puts "rails: #{File.executable?(File.join(ROOT, "bin/rails")) ? "present" : "missing"}"
    options = Selenium::WebDriver::Chrome::Options.new
    %w[--headless=new --no-sandbox --disable-dev-shm-usage --disable-gpu].each { |a| options.add_argument(a) }
    driver = Selenium::WebDriver.for(:chrome, options: options)
    driver.navigate.to("data:text/html,<h1>doctor ok</h1>")
    raise VerificationFailure, "browser did not render the probe page" unless driver.find_element(tag_name: "h1").text == "doctor ok"

    puts "chrome: #{driver.capabilities.browser_version}"
    puts "OK"
  ensure
    driver&.quit
  end
end

def parse_options(argv)
  options = { features: FEATURES.dup, port: 3310, keep: false }
  until argv.empty?
    case (argument = argv.shift)
    when "--all"
      options[:features] = FEATURES.dup
    when "--feature"
      name = argv.shift
      raise VerificationFailure, "--feature needs a name" if name.nil?
      raise VerificationFailure, "unknown feature: #{name}" unless FEATURES.include?(name)

      options[:features] = [name]
    when "--port"
      options[:port] = Integer(argv.shift)
    when "--keep"
      options[:keep] = true
    else
      raise VerificationFailure, "unknown option: #{argument}"
    end
  end
  options
end

begin
  case (command = ARGV.shift)
  when "doctor"
    Doctor.new.run
  when "run", nil
    Verifier.new(**parse_options(ARGV)).run
  else
    warn "usage: bin/verify-reactionview doctor | run [--all] [--feature NAME] [--port PORT] [--keep]"
    exit 1
  end
rescue VerificationFailure => error
  warn "FAIL: #{error.message}"
  exit 1
end
