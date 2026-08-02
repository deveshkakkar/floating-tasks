import unittest

from deployment_preflight import validate_parameters


class DeploymentPreflightTests(unittest.TestCase):
    def test_accepts_account_and_domain_parameters(self):
        self.assertEqual(validate_parameters("477439418849", "floating-brain-dev"), [])

    def test_rejects_invalid_account_id(self):
        self.assertIn("account ID must contain exactly 12 digits", validate_parameters("123", "dev"))

    def test_rejects_invalid_domain_prefix(self):
        self.assertIn(
            "Cognito domain prefix must be lowercase letters, numbers, and hyphens",
            validate_parameters("477439418849", "Floating_Brain"),
        )


if __name__ == "__main__":
    unittest.main()
