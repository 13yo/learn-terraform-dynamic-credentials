module "aws" {
    source = "./aws"

    aws_region = "us-west-2"

    name = "acme-hashi-test"

}

module "google_cloud" {
    source = "./gcp"

    gcp_project_id = "hashitest-427520"
    network_name = "acme-hashi-test"
    region = "us-west1"
}