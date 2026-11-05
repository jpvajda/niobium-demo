# Run your first encrypted job in one command

In this demo you pick two numbers. The script encrypts them, multiplies them while they stay encrypted, then decrypts the answer.

A normal program has to decrypt data before it can do math on it. That is when the numbers are visible. [Niobium](https://niobium.co/) does the multiply on the encrypted numbers instead. The program that multiplies never gets the secret key, so it never sees the two numbers you typed. It returns an encrypted answer, and your machine decrypts that answer and prints it.

Step 1 runs that multiply inside the container on your laptop. Step 2 sends the same encrypted multiply to Niobium's chip in their cloud. The secret key stays on your machine either way.

Learn more in Niobium's [FHE Learning series](https://niobium.co/press/series/fhe-101).

## Prerequisites

- **Docker, running.** Installed is not enough. Open Docker Desktop first, or `docker run` fails.
- **About 4 GB of free disk.** The Niobium image is 3.41 GB unpacked.
- **Internet for the first run.** It downloads about 1 GB once.
- **A terminal.**
- **Step 2 only: a Fog account.** [Request one here](https://console.niobium.co/request-account). Access is granted in batches.


## Setup

```bash
git clone https://github.com/jpvajda/niobium-demo.git
cd niobium-demo
```

## Step 1: Run it locally

> Your numbers stay on your laptop. Nothing is sent to Niobium's cloud. The first run downloads Niobium's public image. That happens inside the command below. There is no separate install.

```bash
docker run --rm -it -v "$PWD":/work -w /work ghcr.io/niobiuminc/fhe-dev:latest bash try-it.sh
```

The terminal will prompt you for two whole numbers. Type them and press Enter after each.

If you type 13 and 21, you'll see something like this:

```
Answer: 13 * 21 = 273 (expected 273, diff 5.28395e-07)
Check: [PASS] 273 ~= 273
Locked files: 9 files, 15736122 bytes
Instructions recorded: 213
Time to lock: 0.12 sec
Time to multiply here: 0.13 sec
Time to open: 0.03 sec
Total: 0.28 sec
Where the multiply ran: on this machine, inside the image. The secret key stayed in this container.
Chip time: not in this receipt. A Fog login is a separate step, and the command still does not print milliseconds on the chip.
Fog: skipped. Add --fog after you have run fog login in this container.
```

- **273** is the answer, so it worked.
- The tiny "diff" is normal. This kind of encryption is approximate.
- **15 MB** of locked files for two small numbers. That's why this is hard, and why Niobium builds a chip for it.
- **213 instructions** to multiply two numbers once.


You can also pass the numbers and skip the questions. This prints `8 * 5 = 40` and `[PASS]`:

```bash
docker run --rm -v "$PWD":/work -w /work ghcr.io/niobiuminc/fhe-dev:latest bash try-it.sh 8 5
```

## Step 2 (optional): Run it on Niobium's chip in the cloud

This sends the same multiply to the Fog, Niobium's cloud.

> You need a Fog account: [request one here](https://console.niobium.co/request-account).

**2a. Log in once.** Put your account email in. Type your password when asked.

```bash
docker run --rm -it -v "$HOME/.fog":/root/.fog ghcr.io/niobiuminc/fhe-dev:latest fog login -u you@example.com
```

After you type the password, the command prints two lines:

```bash
[fog] created key 'fog@<container id>' (prefix fsk_...); wrote token to /root/.fog/credentials
fsk_...
```

The first line means the login worked. The key is saved on your laptop at `~/.fog/credentials`. Inside the container that same folder is `/root/.fog`, because the command mounts it there.

The second line is the full API key. The tool prints it on purpose. You do not need to copy it. Do not paste it into chat, a screenshot, or this repo. Step 2b reads the saved file.

**2b. Run it with `--fog`.**

```bash
docker run --rm -it -v "$PWD":/work -v "$HOME/.fog":/root/.fog -w /work ghcr.io/niobiuminc/fhe-dev:latest bash try-it.sh --fog
```

You get the Step 1 receipt, then the Fog result: job id, bytes sent, and upload time. You can find your results in [Fog Console under Analytics](https://console.niobium.co/analytics)

The script can't show how long the chip itself took. That number (1 ms on my run) is only on the job page in the Niobium console.


