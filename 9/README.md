```bash
docker compose up -d --build
```

```bash
docker exec -it ansible-server bash
```

```bash
sshpass -p 'root' ssh-copy-id -o StrictHostKeyChecking=no root@client1
sshpass -p 'root' ssh-copy-id -o StrictHostKeyChecking=no root@client2
```

```bash
mkdir -p /etc/ansible
echo -e "[clients]\nclient1\nclient2" > /etc/ansible/hosts
```

```bash
ansible clients -m ping
```

```bash
nano /root/info_gather.yml
```

```bash
ansible-playbook /root/info_gather.yml
```

```bash
cat /etc/ansible/IT-Planet/*.txt
```