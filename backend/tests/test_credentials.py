import unittest
from unittest.mock import patch

import credentials


class FakeKeyring:
    def __init__(self):
        self.values = {}

    def get_password(self, service, account):
        return self.values.get((service, account))

    def set_password(self, service, account, value):
        self.values[(service, account)] = value

    def delete_password(self, service, account):
        self.values.pop((service, account), None)


class SystemKeychainTest(unittest.TestCase):
    def test_system_keychain_round_trips_qiniu_credentials(self):
        keyring = FakeKeyring()
        with patch.object(credentials, "keyring", keyring):
            store = credentials.SystemKeychain()
            store.set(credentials.ACCESS_KEY_ACCOUNT, "access")
            store.set(credentials.SECRET_KEY_ACCOUNT, "secret")

            self.assertEqual(store.get(credentials.ACCESS_KEY_ACCOUNT), "access")
            self.assertEqual(store.get(credentials.SECRET_KEY_ACCOUNT), "secret")
            store.delete(credentials.SECRET_KEY_ACCOUNT)
            self.assertIsNone(store.get(credentials.SECRET_KEY_ACCOUNT))


if __name__ == "__main__":
    unittest.main()
