locals {
  test_id        = var.test_id == "" ? random_string.test_id.result : var.test_id
  data_lake_name = "datalake${local.test_id}"
  tags = {
    "test_id" = local.test_id
  }
}
