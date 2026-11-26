output "bucket_name" {
  description = "Назва S3-бакета для зображень і документів Wagtail"
  value       = aws_s3_bucket.media.bucket
}

output "bucket_domain" {
  description = "Регіональний домен бакета для MEDIA_URL"
  value       = "${aws_s3_bucket.media.bucket}.s3.${aws_s3_bucket.media.region}.amazonaws.com"
}

output "role_arn" {
  description = "ARN IAM-ролі IRSA для ServiceAccount застосунку"
  value       = aws_iam_role.django_media.arn
}
