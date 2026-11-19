# my-microservice-project
devops CI/CD test repo


---


## 📚 Lesson 3 Documentation & Guides


Detailed guides and documentation for setting up the development environment in Lesson 3:


- **[Bash Script Installation Guide (`lesson-3/README.md`)](./lesson-3/README.md)**  
  Step-by-step instructions on how to download and execute the automated Bash script (`install_dev_tools.sh`) directly from GitHub, along with a guide on how to initialize and run your Django project.


- **[Ansible Automation Guide (`lesson-3/README-ansible.md`)](./lesson-3/README-ansible.md)**  
  Documentation and instructions for deploying the development environment locally using the Ansible Playbook (`setup_dev_tools.yml`).


---


## 📚 Lesson 4 Documentation & Guides


Detailed guides for the Wagtail project (Django + PostgreSQL + Docker):


- **[Lesson 4 Project Guide (`lesson-4/README.md`)](./lesson-4/README.md)**  
  Overview of the Wagtail project, local development setup, and Docker deployment instructions.


---


## 📚 Lesson 5 Documentation & Guides


Detailed guides for provisioning AWS infrastructure with Terraform (`S3 Backend`, `VPC`, and `ECR`):


- **[Lesson 5 Terraform Infrastructure Guide (`lesson-5/README.md`)](./lesson-5/README.md)**  
  Project structure overview, Terraform initialization/execution commands, and module documentation for `s3-backend`, `vpc`, and `ecr`.


---


## 📚 Lesson 7 Documentation & Guides


Detailed guides for provisioning an Amazon EKS cluster with Terraform, pushing the Docker image to ECR, and deploying the Django/Wagtail application via Helm:


- **[Lesson 7 EKS & Helm Deployment Guide (`lesson-7/README.md`)](./lesson-7/README.md)**  
  Terraform configuration for EKS (`t3.small` node group), ECR Docker image build/push workflow, and Kubernetes deployment instructions.


- **[Django Application Helm Chart (`lesson-7/charts/django-app/`)](./lesson-7/charts/django-app/)**  
  Helm chart templates (`Deployment`, `Service`, `ConfigMap`, `HPA`, and `PostgreSQL`) for running the Django/Wagtail stack on EKS.

