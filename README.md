# Disctracker Annotate

This repository now contains the initial scaffolding for a Vue single-page application that will be delivered via an S3 bucket and CloudFront distribution provisioned by Terraform.

## Project structure

```
.
├── frontend/   # Vue 3 + Vite single-page app
└── infra/      # Terraform configuration for S3/CloudFront delivery
```

### Frontend (Vue + Vite)

The frontend is based on Vite with TypeScript support enabled. Run the following commands from the `frontend/` directory to develop and build the SPA:

```bash
npm install
npm run dev    # local development server
npm run build  # generate production assets in dist/
```

The starter UI mirrors the structure of the ctbus_site frontend while keeping things minimal so we can iterate quickly.

### Infrastructure (Terraform)

The `infra/` folder provisions an S3 bucket locked down with a CloudFront origin access control (OAC) and a distribution configured with managed cache/origin request policies for static content. A minimal example of the variables expected by the module is available in `terraform.tfvars.example`.

Deploy steps:

```bash
cd infra
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Make sure the `index_document_source` path in your `terraform.tfvars` points at the freshly built `frontend/dist/index.html` file and set `asset_directory` to the `frontend/dist` folder so that every generated asset is uploaded alongside the HTML shell.

## Next steps & recommendations

* **Asset deployment automation:** Add a CI workflow that builds the Vite project, uploads the `dist/` directory to S3, and runs `terraform apply`. GitHub Actions with an artifact upload to S3 (using `aws-actions/configure-aws-credentials`) would keep deployments consistent.
* **Infrastructure modularization:** As the project grows, consider extracting the S3 + CloudFront configuration into a reusable Terraform module. That will make it easier to share the pattern across services.
* **Security hardening:** Layer in CloudFront and S3 access logging, attach AWS WAF where appropriate, and consider deploying certificate-managed custom domains once DNS ownership is established.
* **SPA routing:** For more complex routing needs, extend the Terraform configuration to upload an error document and add additional `custom_error_response` blocks for 403 errors to ensure client-side routing works under all conditions.
