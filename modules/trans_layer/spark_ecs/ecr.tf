# ==========================================
# Spark job image: jobs/Dockerfile -> ECR (same pattern as catalog_manager)
# ==========================================

resource "aws_ecr_repository" "spark_job" {
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

# keep only the newest images (ECR free tier = 500 MB; one image is ~1 GB)
resource "aws_ecr_lifecycle_policy" "spark_job" {
  repository = aws_ecr_repository.spark_job.name

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

resource "docker_image" "spark_job" {
  name = "${aws_ecr_repository.spark_job.repository_url}:v1"

  build {
    context    = "${path.module}/jobs"
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  # rebuild when the job code or Dockerfile changes (tests/ don't go in the image)
  triggers = {
    src_sha1 = sha1(join("", [
      filesha1("${path.module}/jobs/Dockerfile"),
      filesha1("${path.module}/jobs/bronze_to_silver.py"),
      filesha1("${path.module}/jobs/transforms.py"),
    ]))
  }

  # destroy also removes the image from the machine that built it
  keep_locally = false
}

resource "docker_registry_image" "spark_job" {
  name = docker_image.spark_job.name
  # destroy also deletes the image from ECR
  keep_remotely = false

  triggers = {
    image_id = docker_image.spark_job.image_id
  }
}
