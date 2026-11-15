# Підключаємо модуль для S3 та DynamoDB
module "s3_backend" {
  source = "./modules/s3-backend"                # Шлях до модуля
  bucket_name = "tfstate-bucket-lesson5"  # Ім'я S3-бакета
  table_name  = "terraform-locks"                # Ім'я DynamoDB
}
