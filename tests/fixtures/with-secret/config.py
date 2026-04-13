# This is a test fixture — not a real secret.
# Gitleaks allowlists the canonical AWS docs example (AKIAIOSFODNN7EXAMPLE)
# to avoid false positives in documentation, so this fixture uses a
# fabricated AKIA that matches the aws-access-token regex without being
# on the allowlist.
AWS_ACCESS_KEY_ID = "AKIAZ4XQFAKEKEYABCDE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzZZZ12345"
