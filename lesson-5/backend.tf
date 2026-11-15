terraform {
  backend "s3" {
    bucket         = "tfstate-bucket-lesson5" # Назва S3-бакета
    key            = "lesson-5/terraform.tfstate"   # Шлях до файлу стейту
    region         = "eu-central-1"                    # Регіон AWS
    dynamodb_table = "terraform-locks"              # Назва таблиці DynamoDB
    encrypt        = true                           # Шифрування файлу стейту
  }
}
