variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "bucket_name" {}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "ap-southeast-2"
}

resource "aws_s3_bucket" "ec2_status_bucket" {
  bucket_prefix = "${var.bucket_name}"
  acl    = "private"
  versioning = 	{
           enabled = true
  }
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = "${aws_iam_role.s3_access_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["${aws_s3_bucket.ec2_status_bucket.arn}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["${aws_s3_bucket.ec2_status_bucket.arn}/*"]
    }
  ]
}
EOF
}

resource "aws_iam_role" "s3_access_role" {
  name = "s3_access_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "s3_access_profile" {
  name = "s3_access_profile"
  role = "s3_access_role"
}


data "aws_ami" "myimage" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}


data "template_file" "user_data_template" {
  template = <<EOF
#!/bin/bash
apt-get update
apt-get install -y python python-pip
pip install awscli

echo "<html>
      <body>
      <h2>
      <center>
      Metadata file in S3
      </h2>
      </center>
      <br><br>
      " >> instance_metadata_file.html

echo "<h4>The EC2 instance metadata:</h4> <ul>" >> instance_metadata_file.html
for metadata in {local-hostname,instance-type,ami-id}
do	
 echo "<li>" >> instance_metadata_file.html
 curl  http://169.254.169.254/latest/meta-data/$metadata >> instance_metadata_file.html
 echo "</li>" >> instance_metadata_file.html
done
echo "</ul>" >> instance_metadata_file.html

date +"<br><br><i>This file was generated on %dth %b %Y at %T hrs %Z</i>"   >> instance_metadata_file.html

echo "</body>
      </html>" >> instance_metadata_file.html

aws s3 cp /instance_metadata_file.html  s3://${aws_s3_bucket.ec2_status_bucket.id}/
EOF

}

resource "aws_launch_configuration" "terra_lc" {
  name_prefix = "terraform-lc-example-"
  image_id = "${data.aws_ami.myimage.image_id}"
  instance_type = "t2.micro"
  user_data = "${data.template_file.user_data_template.rendered}"
  iam_instance_profile = "${aws_iam_instance_profile.s3_access_profile.name}"
}

resource "aws_autoscaling_group" "terraform_group" {
  availability_zones        = ["ap-southeast-2a"]
  name                      = "terraform-instance"
  max_size                  = 1
  min_size                  = 1
  launch_configuration      = "${aws_launch_configuration.terra_lc.name}"
}

output "bucket_arn" {
  value = "${aws_s3_bucket.ec2_status_bucket.arn}"
}
