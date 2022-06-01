# iterable-testing

This is a quick POC of using Terraform to generate AWS certificates, route53 records, and a cloud front distribution in support of Iterable HTTPS click-tracking.

## general notes

- A single certificate is created with SANs in support of multiple click tracking URLs.
- ACM automatically writes DNS challenges to route53.
- A single cloud front distribution is created leveraging the previously mentioned certificate.
- The single cloud front distribution is configured with aliases matching the CN and all SANs on the previously mentioned certificate.
- Route53 CNAME records are created for the CN and all SANs on the previously mentioned certificate. Their values is the cloud front distribution domain name.

## terraform notes

- The first item in the `local.sub_domains` list is used as the CN in the certificate. Remaining items are used as SANs.
- See `provider.tf` for the AWS region used.
