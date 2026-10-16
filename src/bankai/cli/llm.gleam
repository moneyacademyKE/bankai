//// One-shot typed completion. Bankai does not call a model on its own.
//// This command exists so an operator can ask, with the key staying in
//// the environment and the answer coming back as data.

import gleam/json
import gleamunison/llm

pub fn complete(prompt: String) -> Result(json.Json, String) {
  case prompt == "" {
    True -> Error("usage: llm complete <prompt>")
    False ->
      case llm.complete_env(prompt) {
        Ok(text) -> Ok(json.object([#("content", json.string(text))]))
        Error(reason) -> Error(reason)
      }
  }
}
