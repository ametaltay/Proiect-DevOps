#Definirea provider
provider "aws" {
  region = "us-east-1"

}
#Crearea VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "MY_VPC"
  }
}
#Am creat subnet-ul
resource "aws_subnet" "club_manager-subnet" {
  tags = {
    Name = "club_Subnet"
  }
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  depends_on              = [aws_vpc.my_vpc]



}
#define routing table
resource "aws_route_table" "club_route-table" {
  tags = {
    Name = "CLUB_Route_table"
  }
  vpc_id = aws_vpc.my_vpc.id
}
#subnet cu routing table
resource "aws_route_table_association" "Club_Route_Association" {
  subnet_id      = aws_subnet.club_manager-subnet.id
  route_table_id = aws_route_table.club_route-table.id


}
#internet gateway
resource "aws_internet_gateway" "my_IG" {
  tags = {
    Name = "MY_IGW"
  }
  vpc_id     = aws_vpc.my_vpc.id
  depends_on = [aws_vpc.my_vpc]
}
#default route
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.club_route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_IG.id
}
#grup de securitate
resource "aws_security_group" "App_SG" {
  name        = "App_SG"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]

  }

}
#crearea private key pentru logarea pe site
#resource "tls_private_key" "Web-key" {
#algorithm = "RSA"

#}

#salvarea chei publice dupa generare
resource "aws_key_pair" "App-Instance-Key" {
  key_name   = "Web-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDjKgB3q/WLQ0xNu6xZ9XAswULdMWEyRC7MZxI84aIcEUY1+0o6XBLpUd6+KQ6GPcSV17iqsix3W1hGcfBtZFdbHttkbXYtoc8yde73KaTRAu562AD9ZN70s/22Ev5otWCMV+kLIhmWhwWx5qEto25O8Lgzl4CCF1Ov8O5svc1hdbdoMzQ3qUlcWX/BCh25NtCtwvQ8RJqG6YDA2+IcfoM6wcSBdmGMarD3psoUmPPl9Lgi7/bvjo6BSbGFSB60Iy4K8zC4lntNja8qUeJD5lO4H4L0sBU0pOCihcxWfsJnuHDUAXZDuCqKdZcyKr8fOTtdK7IkPWVrlFBA91RTLw45 altay@altay-VirtualBox"

}
#salvarea chei pe local
#resource "local_file" "Web-Key" {
#content  = tls_private_key.Web-Key.private_key_pem
#filename = "Web-Key.pem"
#}
#crearea ec2 
resource "aws_instance" "web" {
  ami           = "ami-09d3b3274b6c5d4aa"
  instance_type = "t2.micro"
  tags = {
    Name = "WebServer"
  }
  #count           = 1
  subnet_id       = aws_subnet.club_manager-subnet.id
  key_name        = "Web-key"
  security_groups = [aws_security_group.App_SG.id]

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "ec2-user"
      #private_key = tls_private_key.Web-Key.private_key_pem
      host = aws_instance.web.public_ip

    }
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"

    ]
  }
}
#crearea unui volum 
resource "aws_ebs_volume" "myebs1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "ebsvol"
  }
}
#atasarea volumu de instanta
resource "aws_volume_attachment" "attach_ebs" {
  depends_on   = [aws_ebs_volume.myebs1]
  device_name  = "/dev/sdh"
  volume_id    = aws_ebs_volume.myebs1.id
  force_detach = true
  instance_id  = aws_instance.web.id
}
#punerea volumu pe instanta
resource "null_resource" "nullmount" {
  depends_on = [aws_volume_attachment.attach_ebs]
  connection {
    type = "ssh"
    user = "ec2-user"
    #private_key = tls_private_key.Web-Key.private_key_pem
    host = aws_instance.web.public_ip

  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh/var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/ametaltay/Proiect-DevOps.git"
    ]
  }
}
#S3 Id
locals {
  s3_origin_id = "s3-origin"
}
#Bucket pentru imagini 
resource "aws_s3_bucket" "clubnewbucket4512" {
  bucket = "clubnewbucket4512"
  acl    = "public-read-write"



  tags = {
    Name        = "clubnewbucket4512"
    Environment = "Prod"
  }
  provisioner "local-exec" {
    command = "git clone https://github.com/ametaltay/Proiect-DevOps.git"

  }

}
#acces public la bucket
resource "aws_s3_bucket_public_access_block" "public_storage" {
  depends_on          = [aws_s3_bucket.clubnewbucket4512]
  bucket              = "clubnewbucket4512"
  block_public_acls   = false
  block_public_policy = false

}
#Incarcare date in S3 
resource "aws_s3_bucket_object" "Object1" {
  depends_on = [aws_s3_bucket.clubnewbucket4512]
  bucket     = "clubnewbucket4512"
  acl        = "public-read-write"
  key        = "user.png"
  source     = "/home/altay/Club-Manager/imgs/user.png"




}
#CloudFront
resource "aws_cloudfront_distribution" "tera-cloufront1" {
  depends_on = [aws_s3_bucket_object.Object1]
  origin {
    domain_name = aws_s3_bucket.clubnewbucket4512.bucket
    origin_id   = local.s3_origin_id
  }
  enabled = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PUT", "POST"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"

      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
#Messajul de succes
resource "null_resource" "result" {
  depends_on = [null_resource.nullmount]
  provisioner "local-exec" {
    command = "echo The website has been deployed >> result.txt "

  }
}




