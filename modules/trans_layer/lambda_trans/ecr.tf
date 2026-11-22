
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

  # rebuild when any file in catalog_manager/ changes (app.py, Dockerfile, ...)
  triggers = {
    src_sha1 = sha1(join("", [for f in fileset("${path.module}/catalog_manager", "**") : filesha1("${path.module}/catalog_manager/${f}")]))
  }

  # destroy also removes the image from the machine that built it
  keep_locally = false
}

resource "docker_registry_image" "catalog_manager" {
  name = docker_image.catalog_manager.name
  # destroy also deletes the image from ECR
  keep_remotely = false

  triggers = {
    image_id = docker_image.catalog_manager.image_id
  }
}
