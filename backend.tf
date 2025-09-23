terraform {
  backend "http" {
    address        = "https://gitlab-tst-01.roscap.com/api/v4/projects/1/terraform/state/terraform"
    lock_address   = "https://gitlab-tst-01.roscap.com/api/v4/projects/1/terraform/state/terraform/lock"
    unlock_address = "https://gitlab-tst-01.roscap.com/api/v4/projects/1/terraform/state/terraform/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    username       = "gitlab-ci-token"
    password       = "${env.CI_JOB_TOKEN}"
  }
}
