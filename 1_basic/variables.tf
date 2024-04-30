variable "model_id" {
  description = "The ID of the foundational model used by the agent."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "agent_name" {
  description = "The agent name."
  type        = string
  default     = "ForexAssistant"
}

variable "agent_desc" {
  description = "The agent description."
  type        = string
  default     = "An assisant that provides forex rate information."
}

variable "action_group_name" {
  description = "The action group name."
  type        = string
  default     = "ForexAPI"
}

variable "action_group_desc" {
  description = "The action group description."
  type        = string
  default     = "The currency exchange rates API."
}

