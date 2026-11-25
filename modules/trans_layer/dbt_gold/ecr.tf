# ==========================================
# dbt image: dbt/Dockerfile (dbt-core + dbt-athena + the project) -> ECR
# Same pattern as spark_ecs/ecr.tf.
# ==========================================

resource "aws_ecr_repository" "dbt" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "dbt" {
  repository = aws_ecr_repository.dbt.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 2 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 2
      }
      action = { type = "expire" }
    }]
  })
}

resource "docker_image" "dbt" {
  name = "${aws_ecr_repository.dbt.repository_url}:v1"

  build {
    context    = "${path.module}/dbt"
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  # rebuild when any file of the dbt project changes (models, tests, config)
  triggers = {
    src_sha1 = sha1(join("", [
      for f in sort(fileset("${path.module}/dbt", "**")) : filesha1("${path.module}/dbt/${f}")
      if !startswith(f, "target/") && !startswith(f, "logs/")
    ]))
  }

  # destroy also removes the image from the machine that built it
  keep_locally = false
}

resource "docker_registry_image" "dbt" {
  name = docker_image.dbt.name
  # destroy also deletes the image from ECR
  keep_remotely = false

  triggers = {
    image_id = docker_image.dbt.image_id
  }
}
