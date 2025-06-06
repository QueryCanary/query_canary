---
title: SSH Tunnel
---

SSH tunnels provide a secure way to connect to your database by routing traffic through an intermediary SSH server. This ensures that sensitive data is encrypted and protected during transit.

It's an easy way to connect QueryCanary to your production database servers, without exposing them to the public web.

### What is a SSH Tunnel?

An SSH tunnel creates a secure connection between QueryCanary.com's runner machines and your remote server. It forwards a local port to a target database port on the remote server, allowing you to securely access the database as if it were running locally.

### When to use a SSH Tunnel?

-   **Secure Connections**: When your database is not directly accessible over the internet.
-   **Firewall Restrictions**: When the database is only accessible from a specific SSH server.
-   **Extra Security**: To encrypt database traffic and prevent unauthorized access.

### Configuration

#### 1. **Gather Required Information**

Before setting up an SSH tunnel, ensure you have the following details:

-   **SSH Server Information**:

    -   Hostname or IP address of the SSH server.
    -   Port number (default is `22`).
    -   Username for SSH authentication.

-   **Database Information**:

    -   Hostname or IP address of the database (from the SSH server's perspective).
    -   Port number (e.g., `5432` for PostgreSQL, `3306` for MySQL).

#### 2. **Enable SSH Tunnel in QueryCanary**

When adding or editing a server in QueryCanary, enable the SSH tunnel and provide the required details:

| Field Name | Description |
| --- | --- |
| **SSH Hostname** | The hostname or IP address of the SSH server. |
| **SSH Port** | The port of the SSH server (default: `22`). |
| **SSH Username** | The username to authenticate with the SSH server. |

We'll save those details and provide you a SSH public key to add to your server.

Here's a configuration example:

-   **SSH Server**:

    -   Hostname: `ssh.example.com`
    -   Port: `22`
    -   Username: `ssh_user`

#### 3. Add the generated public key to your server
QueryCanary will generate each server a unique SSH public key to authorize it's connection to your SSH server. This makes it easy to track & manage the permissions QueryCanary has, which should be extremely limited.

On your SSH server:
```bash
# Create the SSH folder if necessary
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Edit the authorized keys file to add our public key
nano ~/.ssh/authorized_keys
```
Add the QueryCanary SSH key, it should look something like this:
```bash
ecdsa-sha2-nistp256 SoMElOnGVALue== querycanary.com 
```

You can then test the connection to ensure it's properly setup.

### Common Issues

1.  **Failed to Connect to SSH Server**:

    -   Verify the SSH hostname, port, and username.
    -   Ensure the SSH server is reachable from the QueryCanary server.

2.  **Invalid SSH Key**:

    -   Verify that your servers uniquely generated public key is added to the SSH server's `authorized_keys` file.

3.  **Database Connection Issues**:

    -   Ensure the database hostname and port are correct from the SSH server's perspective.
    -   Verify that the database allows connections from the SSH server.

By following this guide, you can securely connect to your database using SSH tunnels in QueryCanary.