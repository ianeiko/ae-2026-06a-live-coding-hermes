# Your first coding agent, in a box

An AI agent running in a throwaway Docker container on your machine, talking to
a model on someone else's GPU. One command, no account on any cloud, no card.

This repo has no code in it. That is the point of the exercise: an agent is not
a program you write, it is a **client** you point at a model. Everything you do
here is configuration — a key, a model name, a container — and by the end you
will know exactly which of those three is which, and which of them survive when
you close the terminal.

```
   your machine                 container                    OpenRouter
   ─────────────                ─────────                    ──────────
   spawn hermes sandbox ─────▶  hermes
                                  │
                                  │  POST /v1/chat/completions
                                  └───────────────────────▶   a model
                                  ◀───────────────────────    (someone's GPU)

   ~/.config/spawn/               ~/.hermes/config.yaml
     openrouter.json ─────────▶     model.default
     (which key)                    (which model)
```

Two boundaries, not one. The **agent** runs on your machine but cannot see your
files. The **model** never runs on your machine at all. Almost every confusing
thing in this exercise is one of those two boundaries biting.

## TL;DR

1. **Account** (§1) — OpenRouter key, *and* the privacy toggle. Skip the toggle and §4 fails.
2. **Tools** (§2) — Docker and `spawn`.
3. **Key** (§3) — `cp .env.example .env`, paste your key. Run everything from the repo root.
4. **Run it** (§4) — `spawn hermes sandbox`, say hi.
5. **Swap the model** (§5) — `/model`, and the 404 that teaches you what free costs.
6. **Watch it vanish** (§6) — the container is throwaway. So is everything you configured in it.

`bash scripts/check.sh` tells you where you are at any point.

Fifteen minutes, no card, no cloud account.

## 1. Account

| Sign up for | Where | You leave with |
| --- | --- | --- |
| OpenRouter | https://openrouter.ai | an account, and a key from https://openrouter.ai/settings/keys |

One router account, hundreds of models behind it. You are not signing up with
Anthropic or OpenAI or NVIDIA here — OpenRouter holds those relationships and
bills you (or doesn't) on one interface.

**Then do the thing everyone skips.** Open
https://openrouter.ai/settings/privacy and enable the free-model training
option.

Free models are free because the provider keeps your prompts. If you have not
opted in, OpenRouter refuses to route to them — and the error you get is a
`404`, which reads like the model doesn't exist. It does exist. Your account
policy filtered it out. §5 shows you the exact message.

You do not need credits for this exercise. Free models are enough.

Checkpoint:

```bash
bash scripts/check.sh
```

Expect `MISSING` lines until §3 — that's the next step, not a problem.

## 2. Tools

Two things, both one-liners.

```bash
brew install --cask docker                                  # macOS — Windows: Appendix B
curl -fsSL https://openrouter.ai/labs/spawn/cli/install.sh | bash
```

**Start Docker Desktop and leave it running.** Installing Docker is not the same
as running it; `spawn` needs the daemon up, and the error when it isn't is not
obvious.

`spawn` is a launcher: it puts a coding agent on some computer for you. The
computer can be a cloud VM (`spawn hermes hetzner`) or — here — a Docker
container on your own machine (`spawn hermes sandbox`). Same agent either way.
We use `sandbox` because it costs nothing and needs no cloud account.

Checkpoint:

```bash
bash scripts/check.sh
```

## 3. Key

Copy the template and put your key in it:

```bash
cp .env.example .env
$EDITOR .env          # OPENROUTER_API_KEY=sk-or-v1-...
```

`spawn` reads `.env` from the directory you run it in. That is the whole
mechanism — no export, no shell profile, no `~/.aws`-style dotfile to hunt for.

Two consequences, and both bite:

- **It must be the directory you are standing in.** `.env` is read from the
  current working directory only; `spawn` does not walk up the tree looking for
  one. Run every command in this README from the repo root, or your key is
  invisible.
- **This file is a live credential sitting in a git repo.** It is in
  `.gitignore` already — check that it stays there. `.env.example` is the one
  that gets committed, and it has no key in it. This is the oldest way in the
  world to leak a key, and the reason the pattern is *template committed, real
  file ignored*.

`bash scripts/check.sh` fails loudly if git ever starts tracking `.env`.

### Where the key actually goes

Worth following, because it explains a confusing thing in §6:

```
./.env  ──▶  spawn (your machine)  ──▶  ~/.spawnrc (container)  ──▶  hermes
```

`spawn` reads your file, then writes the key into a shell profile *inside* the
container, which the agent's launch command sources. Hermes never reads your
`.env` — it reads an environment variable that spawn put there.

Hermes has a `.env` of its own (`hermes config env-path` prints
`/root/.hermes/.env`), and it is not this one. It lives in the container and
dies with it. If you ever go looking for "the hermes config file" and find it
empty of keys, that's why.

If you prefer an export, that still works and takes precedence:

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
```

`spawn` also caches a key it has seen before in `~/.config/spawn/openrouter.json`,
so a machine that worked last week may work today with no `.env` at all. That is
convenient and it is also how you end up debugging the wrong key — the checker
prints which of the three sources it found.

Checkpoint:

```bash
bash scripts/check.sh      # expect: all set — go to §4
```

The script also spends one API call proving the key actually works and that the
privacy toggle from §1 is on. A key that authenticates but can't reach a free
model is the single most common way to get stuck here.

## 4. Run it

```bash
spawn hermes sandbox --name hermes-lab
```

First run pulls a container image — a few minutes, once. Then you land in a
prompt:

```
Welcome to Hermes Agent! Type your message or /help for commands.
```

Say something:

```
hi, how are you?
```

Four things worth stopping on:

- **You are not on your machine any more.** The shell prompt is inside the
  container. `ls` in there shows the container's filesystem, not yours. This is
  the sandbox part of "sandbox": the agent cannot touch your files, which is
  also why it cannot help with your files.
- **The model is somewhere else again.** Your message left the container, went
  to OpenRouter, and came back. The agent is a client; the intelligence is
  rented.
- **`/help` lists slash commands.** They are handled by the agent locally and
  never reach the model — that's why `/model` can work even when the model
  can't.
- **A warning about `tirith security scanner ... not available`** is normal in
  the sandbox and not your problem.

Leave the session open for §5.

## 5. Swap the model

The model is not baked into the agent. Change it mid-conversation:

```
/model nvidia/nemotron-3-ultra-550b-a55b:free
```

```
✓ Model switched: nvidia/nemotron-3-ultra-550b-a55b:free
  Provider: OpenRouter
  Context: 262,144 tokens
  Max output: 235,929 tokens
  Capabilities: reasoning, tools, structured output, open weights
  (session only — add --global to persist)
```

Now send another message. Same conversation, different brain. Nothing else
changed — not the agent, not your key, not the container.

**That is the whole lesson of this repo.** A model id is a string. The interface
behind it (`POST /v1/chat/completions`) is the same for every model on
OpenRouter, which is why swapping one costs you a single line and why the agent
neither knows nor cares what it is talking to.

### The 404 that isn't a 404

If you skipped the privacy toggle in §1, that message fails like this:

```
⚠️  API call failed (attempt 1/3): NotFoundError [HTTP 404]
   🔌 Provider: openrouter  Model: nvidia/nemotron-3-ultra-550b-a55b:free
   📝 Error: HTTP 404: 0 endpoints out of 1 requested are available matching
   your guardrail restrictions and data policy. We removed them for the
   following reasons (an endpoint may have matched multiple reasons):
   Free model training violation (account settings): 1 endpoint excluded
```

Read it carefully, because it is a good error pretending to be a bad one.
`0 endpoints out of 1` — the model exists, OpenRouter found exactly one place
serving it, and then *your own account settings* removed that place. Nothing is
broken. You asked for something free without agreeing to the price.

Go back to §1, flip the toggle, send the message again.

Free models also queue. A `:free` request that hangs for thirty seconds is
working; it is just behind everyone else's. The paid twin of any model is the
same id without `:free`.

### Session vs persistent

Note the last line: **`(session only — add --global to persist)`**.

```
/model nvidia/nemotron-3-ultra-550b-a55b:free --global
```

That writes `model.default` into `~/.hermes/config.yaml` *inside the container*.
Which brings us to the punchline.

## 6. Watch it vanish

Exit the agent. Then look at what you have:

```bash
docker ps -a --filter name=hermes-lab
docker inspect hermes-lab --format '{{json .Mounts}}'
```

```
[]
```

**Nothing from your machine is mounted into that container, and nothing from
that container is mounted back.** The `--global` you just ran wrote a config
file onto a disk that exists only as long as the container does. Start a fresh
sandbox and you are back to the default model, with no trace of §5.

This is not a bug, it is the deal you took in §2. You wanted an agent that
cannot touch your files; the price is that it also cannot keep anything. A
sandbox is a `modal run`, never a `modal deploy` — it lives for one session.

So the durable way to choose a model is to say it at launch, from your machine,
where your shell history lives:

```bash
spawn hermes sandbox --name hermes-lab --model nvidia/nemotron-3-ultra-550b-a55b:free
```

The key survives (it's in *your* `~/.config/spawn/`). The model choice survives
(it's in your command). Everything you typed *inside* the box does not.

That distinction — configuration that lives on your side of the boundary versus
configuration that lives on theirs — is the thing to carry out of this exercise.

Housekeeping:

```bash
docker ps -a --filter name=hermes-lab      # is it still there?
docker rm -f hermes-lab                    # throw it away
spawn status                               # what spawn thinks it launched
spawn list                                 # re-run a previous launch
```

## What you actually learned

| You typed | What it means |
| --- | --- |
| `spawn hermes sandbox` | run this agent over there — where "there" is a container on your own machine |
| `.env` in the repo root | the one credential — read by `spawn`, from *this* directory only |
| `.env.example` | the committed half of the pattern; the real one is gitignored |
| `/model <id>` | swap the brain, this session only |
| `/model <id> --global` | swap the brain, until the container dies |
| `--model <id>` at launch | swap the brain durably, because the command is yours |
| `:free` | the provider keeps your prompts; your account must agree (§1) |
| `404: 0 endpoints out of 1` | the model exists; your policy filtered it |
| `Mounts: []` | nothing crosses the boundary that you did not send |

An agent is a loop around an HTTP call. `spawn` chose the computer, Docker drew
the boundary, OpenRouter chose the model, and Hermes was the loop. None of those
four are the same decision, and every confusing failure in this exercise came
from mixing two of them up.

## Appendix A — the lazy way

If you'd rather hand §2–§4 to Claude Code, open `claude` in this repo and paste:

> Set this machine up to run the Hermes sandbox exercise in this repo's README.
> Install Docker and the `spawn` CLI if they're missing, and tell me if I need to
> start Docker Desktop myself. I'll paste my OpenRouter key when you ask — put it
> in the environment, never in a file in this repo. Run `bash scripts/check.sh`
> after each step and fix every `MISSING` line until it prints `all set`; `todo`
> lines are not yours to fix. Then give me the exact `spawn hermes sandbox`
> command to run in another terminal — don't launch the interactive agent
> yourself, it needs my terminal. Don't change anything in ~/.hermes.

## Appendix B — Windows

`spawn`'s sandbox is Docker, and Docker on Windows wants WSL2. Install that
first; the Docker Desktop installer will offer to do it and then ask you to
reboot.

| Tool | Install (PowerShell) |
| --- | --- |
| Docker Desktop | `winget install Docker.DockerDesktop` |
| git | `winget install Git.Git` |
| Claude Code | `npm i -g @anthropic-ai/claude-code` |

`scripts/check.sh` is bash — run it from **Git Bash** (ships with
[Git for Windows](https://git-scm.com/download/win)). The `export` in §3 is
`$env:OPENROUTER_API_KEY = "sk-or-v1-..."` in PowerShell, but if you run
everything from Git Bash the README works unchanged.

## Troubleshooting

| What you see | Cause | Fix |
| --- | --- | --- |
| `404 ... Free model training violation (account settings)` | free models need the privacy opt-in | §1 — https://openrouter.ai/settings/privacy |
| `404` on a model you can see on openrouter.ai | same thing, or you typo'd the id | ids are case-sensitive and include the vendor: `nvidia/nemotron-3-ultra-550b-a55b:free` |
| `Cannot connect to the Docker daemon` | Docker installed but not running | §2 — start Docker Desktop and wait for the whale to settle |
| `OPENROUTER_API_KEY -- not set` but `.env` exists | you're not standing in the repo root | §3 — `.env` is read from the cwd only, never a parent directory |
| checker says the key came from `~/.config/spawn/...` | spawn cached a key from an earlier run; your `.env` is empty or absent | §3 — that's a different key than the one you just pasted |
| `.env is TRACKED BY GIT` | it got committed before `.gitignore` existed | `git rm --cached .env`. If it was ever pushed, rotate the key — deleting the file does not delete the history |
| `spawn: command not found` | installer put it in `~/.local/bin`, not on `PATH` | reopen your terminal, or `export PATH="$HOME/.local/bin:$PATH"` |
| First run sits at "pulling" for minutes | it's downloading the agent image, once | let it finish; later runs are seconds |
| A `:free` message hangs for 30s+ | free endpoints queue behind paid traffic | wait, or drop `:free` for the paid twin (costs credits) |
| `/model` worked but the message still failed | `/model` is local; it never asked the provider anything | the switch was fine, the *call* was refused — read the 404, §5 |
| Model is back to the default after a restart | the container was thrown away, §6 | pass `--model` to `spawn` instead |
| Agent can't see your project files | by design — nothing is mounted, §6 | that's the sandbox; a cloud spawn or `spawn hermes local` is the other trade |
| `tirith security scanner enabled but not available` | not shipped in the sandbox image | ignore it |
| `hermes status` shows `OpenRouter ✗ (not set)` | you ran it via `docker exec`, which skips the shell profile holding the key | check inside the agent session instead |
