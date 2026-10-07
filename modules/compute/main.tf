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
