locals {
    cluster_name = "eks-lab"
}


locals {
    vpc_cidr = "10.0.0.0/16"
}

locals {
    tags = {
        Project = "eks-lab"
        ManagedBy = "terraform"
    }
}