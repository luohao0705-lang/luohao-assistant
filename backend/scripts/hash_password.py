import getpass

from pwdlib import PasswordHash


if __name__ == "__main__":
    print(PasswordHash.recommended().hash(getpass.getpass("Password: ")))
