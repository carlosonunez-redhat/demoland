resource "aws_acmpca_certificate_authority" "ca_disconnected" {
  type = "ROOT"
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"
    subject {
      common_name = "disconnected-ca-${random_string.ca-suffix.result}"
    }
  }

  permanent_deletion_time_in_days = 21
}


resource "aws_acmpca_certificate" "ca_disconnected" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.ca_disconnected.arn
  certificate_signing_request = aws_acmpca_certificate_authority.ca_disconnected.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_permission" "ca_disconnected_acm_renewal" {
  certificate_authority_arn = aws_acmpca_certificate_authority.ca_disconnected.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}

resource "aws_acmpca_certificate_authority_certificate" "ca_disconnected" {
  certificate_authority_arn = aws_acmpca_certificate_authority.ca_disconnected.arn

  certificate       = aws_acmpca_certificate.ca_disconnected.certificate
  certificate_chain = aws_acmpca_certificate.ca_disconnected.certificate_chain
}
