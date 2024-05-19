output "elb_dns_name" {
  description = "DNS address for Load balancer"
  value       = aws_elb.ec2_website.dns_name
}