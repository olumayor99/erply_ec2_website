output "elb_dns_name" {
  description = "DNS address for Load balancer"
  value       = aws_lb.ec2_website.dns_name
}