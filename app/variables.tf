variable "test_id" {
  default = ""
  type    = string
}

variable "region" {
  #default = "eastus2"
  default = "westus2"
  type    = string
}

variable "logged_user_objectId" {
  type        = string
  description = "Object ID of the existing service principal that will be used for communication between services"
}