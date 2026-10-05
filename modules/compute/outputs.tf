output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "asg_name" {
  description = "Name of the Auto Scaling group"
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the Auto Scaling group"
  value       = aws_launch_template.app.id
}

output "cpu_alarm_name" {
  description = "Name of the CloudWatch CPU alarm (empty when enable_cpu_alarm is false)"
  value       = var.enable_cpu_alarm ? aws_cloudwatch_metric_alarm.asg_cpu_high[0].alarm_name : ""
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving alarm notifications (empty when enable_cpu_alarm is false)"
  value       = var.enable_cpu_alarm ? aws_sns_topic.alerts[0].arn : ""
}
