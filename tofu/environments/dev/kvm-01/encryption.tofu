# State encryption — key provider is supplied at runtime via TF_ENCRYPTION env var.
# Add STATE_ENCRYPTION_PASSPHRASE to setup.env; the justfile constructs TF_ENCRYPTION from it.
# enforced = true prevents accidentally writing unencrypted state if TF_ENCRYPTION is missing.
terraform {
  encryption {
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
