# Task3

This Terraform configuration creates the autoscaling group for the application that returns the "Hello World!" page. Request are routed to the application instances
through the HTTP API gateway that is connected to the internal application load balancer using the VPC link. The application instances are still accessable to check if
they are working properly but the access can be restricted using the `associate_public_ip_address = false` argument in the `aws_launch_configuration` resource. The
database is created but is not accessable because it is not clear from the task how everything should be configured.
