import { Controller } from "@hotwired/stimulus"
import { useState } from "reactionview"

export default class extends Controller {
  connect() {
    useState(this)
  }

  // <name>Changed mirrors the template's own state name (composing), so
  // this stays in sync without any duplicate source of truth.
  composingChanged(composing) {
    if (composing) this.element.querySelector("textarea")?.focus()
  }
}
