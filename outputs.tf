output "alb_dns_name" {
  description = "DNS do Application Load Balancer para acessar o WordPress"
  value       = aws_lb.main.dns_name
}