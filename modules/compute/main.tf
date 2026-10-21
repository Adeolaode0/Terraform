data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name_prefix}-app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [var.instance_sg_id]

  # Require IMDSv2: closes the SSRF-style metadata theft path on compromised apps
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Encrypt the root volume at rest (AWS-managed KMS key)
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted   = true
      volume_size = 20
      volume_type = "gp3"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
    echo "<h1>Hello from $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}-app" }
  }
}

resource "aws_lb" "app" {
  name                       = "${var.name_prefix}-app-alb"
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = var.alb_deletion_protection
}

# --------------------------------------------------------------------------
# ALB access logs (commented example)
#
# Uncomment the pieces below to ship ALB request logs to S3. Useful for
# debugging 5xx errors, auditing traffic, or running Athena queries.
# Logs land under s3://<bucket>/<prefix>/AWSLogs/<account-id>/... with a
# typical delivery lag of about 5 minutes.
#
#   # 1. Log bucket with an ELB write policy (add a data source for
#   #    aws_caller_identity, or hard-code your account ID):
#
#   resource "aws_s3_bucket" "alb_access_logs" {
#     bucket        = "${var.name_prefix}-alb-access-logs"
#     force_destroy = true # dev only; remove for production
#   }
#
#   resource "aws_s3_bucket_policy" "alb_access_logs" {
#     bucket = aws_s3_bucket.alb_access_logs.id
#     policy = jsonencode({
#       Version = "2012-10-17"
#       Statement = [{
#         Effect    = "Allow"
#         Principal = { Service = "elasticloadbalancing.amazonaws.com" }
#         Action    = "s3:PutObject"
#         Resource  = "${aws_s3_bucket.alb_access_logs.arn}/*"
#         Condition = {
#           StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
#           ArnLike      = { "aws:SourceArn" = aws_lb.app.arn }
#         }
#       }]
#     })
#   }
#
#   # 2. Wire the bucket into the load balancer (merge with aws_lb.app):
#
#   access_logs {
#     bucket  = aws_s3_bucket.alb_access_logs.id
#     prefix  = "alb"
#     enabled = true
#   }
#
# Cost hygiene: add an S3 lifecycle rule expiring log objects after 90 days
# so old logs do not accumulate indefinitely.
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# WAFv2 web ACL association (commented example)
#
# Uncomment the pieces below to put AWS WAFv2 in front of the ALB. Shields
# the app from common web exploits (SQL injection, cross-site scripting)
# and throttles request floods from a single IP.
#
#   # 1. Web ACL with AWS managed rules (REGIONAL scope: ALBs are regional):
#
#   resource "aws_wafv2_web_acl" "app" {
#     name  = "${var.name_prefix}-app-waf"
#     scope = "REGIONAL"
#
#     default_action {
#       allow {}
#     }
#
#     # AWS Managed Common Rule Set: OWASP Top 10 coverage (SQLi, XSS, etc.)
#     rule {
#       name     = "AWSManagedRulesCommonRuleSet"
#       priority = 10
#
#       override_action {
#         none {}
#       }
#
#       statement {
#         managed_rule_group_statement {
#           name        = "AWSManagedRulesCommonRuleSet"
#           vendor_name = "AWS"
#         }
#       }
#
#       visibility_config {
#         cloudwatch_metrics_enabled = true
#         metric_name                = "${var.name_prefix}-app-waf-common"
#         sampled_requests_enabled   = true
#       }
#     }
#
#     # Rate-based rule: blocks IPs sending more than 2,000 requests
#     # in any 5-minute window
#     rule {
#       name     = "RateLimitPerIP"
#       priority = 20
#
#       action {
#         block {}
#       }
#
#       statement {
#         rate_based_statement {
#           limit              = 2000
#           aggregate_key_type = "IP"
#         }
#       }
#
#       visibility_config {
#         cloudwatch_metrics_enabled = true
#         metric_name                = "${var.name_prefix}-app-waf-rate"
#         sampled_requests_enabled   = true
#       }
#     }
#
#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "${var.name_prefix}-app-waf"
#       sampled_requests_enabled   = true
#     }
#   }
#
#   # 2. Associate the web ACL with the ALB:
#
#   resource "aws_wafv2_web_acl_association" "app" {
#     resource_arn = aws_lb.app.arn
#     web_acl_arn  = aws_wafv2_web_acl.app.arn
#   }
#
# Cost hygiene: a web ACL is about $5/month plus $1 per million requests,
# with AWS managed rule groups adding about $1 more per million requests.
# Deploy new managed rules in count mode first (override_action { count {} })
# so you can inspect sampled requests for false positives before blocks
# start dropping legitimate traffic.
# --------------------------------------------------------------------------

resource "aws_lb_target_group" "app" {
  name     = "${var.name_prefix}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path = "/"
    port = "80"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.name_prefix}-app-asg"
  vpc_zone_identifier = var.public_subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.name_prefix}-app-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.target_cpu_utilization
  }
}
