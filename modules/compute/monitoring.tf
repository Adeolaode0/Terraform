# Observability: a CloudWatch alarm on average ASG CPU, delivered to an SNS topic.
# Everything here is gated by var.enable_cpu_alarm; email delivery is opt-in via
# var.notification_email (subscribers must confirm the confirmation email AWS sends).

resource "aws_sns_topic" "alerts" {
  count = var.enable_cpu_alarm ? 1 : 0
  name  = "${var.name_prefix}-app-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_cpu_alarm && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  count               = var.enable_cpu_alarm ? 1 : 0
  alarm_name          = "${var.name_prefix}-app-asg-cpu-high"
  alarm_description   = "Average CPU of ASG ${aws_autoscaling_group.app.name} above ${var.cpu_alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]
}
