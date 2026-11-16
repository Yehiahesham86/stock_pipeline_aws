
resource "aws_ecr_repository" "catalog_manager" {
  name                 = "stock-bronze-catalog-manager"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "docker_image" "catalog_manager" {
  name = "${aws_ecr_repository.catalog_manager.repository_url}:v1"

  build {
    context    = "${path.module}/catalog_manager"
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  keep_locally = true
}

resource "docker_registry_image" "catalog_manager" {
  name          = docker_image.catalog_manager.name
  keep_remotely = true

  triggers = {
    image_id = docker_image.catalog_manager.image_id
  }
}
