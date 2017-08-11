# Tips for using Ansible Vault to store a password in a yaml file

Sometimes we want to encrypt a file so that we can check it into a repo for later use.
Then we want some way to decrypt the file.

Create a password for yourself and put it into a file.  We'll call it vault_pass.txt.

```
$ echo mysimplepassword > vault_pass.txt
```

For ansible-vault's most simple usage, you can just do simple encrypt and decrypt of
a file.  For example:

```
$ echo "Can you see this?" > myfile.txt
$ cat myfile.txt 
Can you see this?

$ ansible-vault encrypt myfile.txt --vault-password-file ./vault_pass.txt
Encryption successful

$ cat myfile.txt 
$ANSIBLE_VAULT;1.1;AES256
36303861363130373932633165643134363666346639356461383830633131346364336131393064
6466616334346331353232666234386662633839356237390a656538373664393266613935346235
38653566613030663063346464613166643363656264353235663038306331376435393931396235
6363633539663137650a353763656434353862636465666562663739396233393362633530383238
34376234373737343265393934396237643133646265626430383465663131663137

$ ansible-vault decrypt myfile.txt --vault-password-file ./vault_pass.txt
Decryption successful

$ cat myfile.txt 
Can you see this?
```

Below is a more practical use in an Ansible playbook.

Let's make a simple Ansible playbook that uses the localhost.  This simple playbook
just runs on localhost (the host you're running on) and runs the 'keyup' role.  The purpose
of the 'keyup' role will become apparent below.

```
$ cat keyup.yaml 
---
- hosts: localhost

  roles:
    - { role: keyup }
```

Let's make a directory structure for a small role that uses some secret value stored in your
mykeys.yaml file.

```
$ tree keyup
keyup
├── tasks
│   └── main.yaml
└── vars
    └── mykeys.yaml

```

The main task (in main.yaml) looks like this:

```
$ cat keyup/tasks/main.yaml 
---
- include_vars: mykeys.yaml

- name: Get the password and dump it to a file called /tmp/cloud.txt
  no_log: True
  copy:
    content="{{opspasswd}}"
    dest=/tmp/cloud.txt
```

The 'keyup' role gets the value of 'opspasswd' (obtained from the mykeys.yaml file) and places it
into a file at /tmp/cloud.txt on the localhost using the 'copy' module.  Once that file is in place, you
can use the contents as needed.

The mykeys.yaml, containing the password (before encryption), looks like this:

```
$ cat keyup/vars/mykeys.yaml
opspasswd: elloHorldW
```

To encrypt using your password file above, do this:
```
$ ansible-vault encrypt roles/keyup/vars/mykeys.yaml --vault-password-file ./.vault_pass.txt 
Encryption successful
```

Now you can checkin all files including the encrypted mykeys.yaml file.

To run the Ansible playbook, do this:

```
$ ansible-playbook -i localhost, -c local keyup.yaml --vault-password-file ./vault_pass.txt
```

You can cat the file /tmp/cloud.txt and you should see the password.

As before, you can decrypt using your password file above, do this:

```
$ ansible-vault decrypt roles/keyup/vars/mykeys.yaml --vault-password-file ./vault_pass.txt
Decryption successful
```












