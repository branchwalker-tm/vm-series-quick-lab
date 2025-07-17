###### Define variables ######

variable "aws_region" {
  description = "The AWS region to deploy into."
  type        = string
  default     = "us-east-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1", "eu-central-1", "ap-southeast-2"], var.aws_region)
    error_message = "Please provide a valid AWS region (e.g. us-east-1)."
  }
}

variable "my_ip_address" {
  description = "Your public IP address for SSH access to the bastion host (e.g., 'X.X.X.X/32')."
  type        = string
  default     = "0.0.0.0/0" # WARNING: Change this to your public IP for production
}

###### Configure the AWS provider ######

provider "aws" {
  region = var.aws_region
}

###### VPC and Subnets ######

resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "PaloAlto-Ubuntu-Lab-VPC"
  }
}

resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "PaloAlto-Ubuntu-Lab-IGW"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "PaloAlto-Ubuntu-Public-Subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "PaloAlto-Ubuntu-Private-Subnet"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

######  Route Tables ######

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }

  tags = {
    Name = "PaloAlto-Ubuntu-Public-RT"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "PaloAlto-Ubuntu-Private-RT"
  }
}

resource "aws_route_table_association" "private_rt_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

######  Security Groups ######

resource "aws_security_group" "paloalto_mgmt_sg" {
  name        = "paloalto-mgmt-sg-${random_id.suffix.hex}"
  description = "Allow SSH and HTTPS to Palo Alto management interface"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] ###### WARNING: NOT RECOMMENDED FOR PRODUCTION ######
    description = "Allow SSH for management"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] ###### WARNING: NOT RECOMMENDED FOR PRODUCTION ######
    description = "Allow HTTPS for management GUI"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "PaloAlto-Mgmt-SG"
  }
}

resource "aws_security_group" "paloalto_untrust_sg" {
  name        = "paloalto-untrust-sg-${random_id.suffix.hex}"
  description = "Allow necessary inbound to Palo Alto untrust interface"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP inbound"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS inbound"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH inbound"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "PaloAlto-Untrust-SG"
  }
}

resource "aws_security_group" "paloalto_trust_sg" {
  name        = "paloalto-trust-sg-${random_id.suffix.hex}"
  description = "Palo Alto trust interface security group"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
    description = "Allow all traffic from private subnet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "PaloAlto-Trust-SG"
  }
}

resource "aws_security_group" "ubuntu_private_sg" {
  name        = "ubuntu-private-sg-${random_id.suffix.hex}"
  description = "Allow traffic only from Palo Alto trust interface and bastion host"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.paloalto_trust_sg.id]
    description     = "Allow all from Palo Alto Trust Interface"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow SSH from Bastion Host"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] ###### Outbound will be routed via Palo Alto Networks firewall
    description = "Allow all outbound traffic (routed via firewall)"
  }

  tags = {
    Name = "Ubuntu-Private-SG"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}


######  Palo Alto Networks VM-Series Firewall Network Interfaces ######

resource "aws_network_interface" "palo_alto_mgmt_eni" {
  subnet_id         = aws_subnet.public_subnet.id
  security_groups   = [aws_security_group.paloalto_mgmt_sg.id]
  private_ips       = ["10.0.1.5"] ###### Assign a specific private IP for management
  source_dest_check = true       ###### Management interface typically has source/dest check enabled

  tags = {
    Name = "PaloAlto-Mgmt-ENI"
  }
}

resource "aws_network_interface" "palo_alto_untrust_eni" {
  subnet_id         = aws_subnet.public_subnet.id
  security_groups   = [aws_security_group.paloalto_untrust_sg.id]
  private_ips       = ["10.0.1.10"] ###### Assign a specific private IP in the public subnet for untrust
  source_dest_check = false

  tags = {
    Name = "PaloAlto-Untrust-ENI"
  }
}

resource "aws_network_interface" "palo_alto_trust_eni" {
  subnet_id         = aws_subnet.private_subnet.id
  security_groups   = [aws_security_group.paloalto_trust_sg.id]
  private_ips       = ["10.0.2.10"] ###### Assign a specific private IP in the private subnet for trust
  source_dest_check = false

  tags = {
    Name = "PaloAlto-Trust-ENI"
  }
}

######  Palo Alto Networks VM-Series Firewall EC2 Instance ###### 

resource "aws_instance" "palo_alto_vm_series" {
  ami                   = "ami-01e981c186be7d73b" ###### Palo Alto AMI ID for us-east-2
  instance_type         = "m5.xlarge"
  key_name              = "<YOUR_SSH_KEYPAIR_NAME>"
  disable_api_termination = false

  ###### All network interfaces are attached as explicit blocks ######
  network_interface {
    device_index          = 0
    network_interface_id  = aws_network_interface.palo_alto_mgmt_eni.id
    delete_on_termination = false ###### Typically false for pre-created ENIs
  }

  network_interface {
    device_index          = 1
    network_interface_id  = aws_network_interface.palo_alto_untrust_eni.id
    delete_on_termination = false
  }

  network_interface {
    device_index          = 2
    network_interface_id  = aws_network_interface.palo_alto_trust_eni.id
    delete_on_termination = false
  }

  tags = {
    Name = "PaloAlto-VM-Series"
  }
}

###### Elastic IP for the Palo Alto Networks Untrust (Public) Data Plane Interface ######
resource "aws_eip" "palo_alto_untrust_eip" {
  domain = "vpc"
  network_interface = aws_network_interface.palo_alto_untrust_eni.id
  associate_with_private_ip = "10.0.1.10"

  tags = {
    Name = "PaloAlto-VM-Series-Untrust-EIP"
  }
}

###### Elastic IP for the Palo Alto Networks Management Interface ######
resource "aws_eip" "palo_alto_mgmt_eip" {
  domain = "vpc"
  network_interface = aws_network_interface.palo_alto_mgmt_eni.id
  associate_with_private_ip = "10.0.1.5"

  tags = {
    Name = "PaloAlto-VM-Series-Mgmt-EIP"
  }
}

######  Bastion Host ######

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg-${random_id.suffix.hex}"
  description = "Allow SSH access to the bastion host"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_address]
    description = "Allow SSH from my IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "Bastion-SG"
  }
}

resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.ubuntu_latest.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  security_groups        = [aws_security_group.bastion_sg.id]
  key_name               = "<YOUR_SSH_KEYPAIR_NAME>"
  associate_public_ip_address = true # Bastion needs a public IP

  tags = {
    Name = "Bastion-Host"
  }
}


######  Ubuntu VM ######

data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"] ###### Canonical's AWS account ID for Ubuntu AMIs

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "ubuntu_vm" {
  ami                         = data.aws_ami.ubuntu_latest.id ###### Dynamically get the latest Ubuntu AMI ID ######
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_subnet.id
  security_groups             = [aws_security_group.ubuntu_private_sg.id]
  key_name                    = "<YOUR_SSH_KEYPAIR_NAME>"
  associate_public_ip_address = false

  tags = {
    Name = "Ubuntu-Lab-VM"
  }
}

######  Update Private Route Table to point to Palo Alto Trust Interface ######

resource "aws_route" "private_subnet_default_route_to_paloalto" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.palo_alto_trust_eni.id
  depends_on = [
    aws_instance.palo_alto_vm_series,
    aws_network_interface.palo_alto_trust_eni
  ]
}


######  Outputs ###### 

output "palo_alto_mgmt_public_ip" {
  description = "Public IP address of the Palo Alto Networks VM-Series Management Interface"
  value       = aws_eip.palo_alto_mgmt_eip.public_ip
}

output "palo_alto_untrust_public_ip_eip" {
  description = "Elastic IP address of the Palo Alto Networks VM-Series Untrust Interface"
  value       = aws_eip.palo_alto_untrust_eip.public_ip
}

output "ubuntu_private_ip" {
  description = "Private IP address of the Ubuntu VM"
  value       = aws_instance.ubuntu_vm.private_ip
}

output "palo_alto_trust_private_ip" {
  description = "Private IP address of the Palo Alto Networks VM-Series Trust Interface"
  value       = aws_network_interface.palo_alto_trust_eni.private_ip
}

output "palo_alto_mgmt_private_ip" {
  description = "Private IP address of the Palo Alto Networks VM-Series Management Interface"
  value       = aws_network_interface.palo_alto_mgmt_eni.private_ip
}

output "palo_alto_untrust_private_ip" {
  description = "Private IP address of the Palo Alto Networks VM-Series Untrust Interface"
  value       = aws_network_interface.palo_alto_untrust_eni.private_ip
}

output "bastion_public_ip" {
  description = "Public IP address of the Bastion Host"
  value       = aws_instance.bastion_host.public_ip
}
