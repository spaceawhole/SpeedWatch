# SpeedWatch

Scheduled internet speed tests for Windows, recorded on your own PC, with a report you
can show your internet provider when the speed you get is not the speed you pay for.

> **Windows only.** SpeedWatch needs **Windows 10 or Windows 11**. It does **not** work on
> macOS or Linux: it is built on Windows Task Scheduler, Windows PowerShell and a Windows
> window toolkit, none of which exist on a Mac.

## Install in 4 steps

1. **Download** — on this page press the green **Code** button, then **Download ZIP**.
2. **Extract** the zip into a folder you will keep, for example `Documents\SpeedWatch`.
   Not your Downloads folder or a temporary folder: wherever the folder is, that is
   where SpeedWatch is installed.
3. **Double-click `Install.cmd`** in that folder. If Windows shows *"Windows protected
   your PC"*, choose **More info → Run anyway** (it is a plain text file you can open in
   Notepad first if you want to see what it does). No administrator rights are needed.
4. **Open SpeedWatch** from the new desktop shortcut, type your plan's download speed in
   **Mb/s** (a "1000 megas" plan is `1000`), press **Save**, and check it says **ON**.

That's it. Tests now run at the times shown in the panel (14:00 by default; add or
remove times there), and a test that was missed because the PC was off runs as soon
as it is back on.

## Remove in 2 steps

1. **Double-click `Uninstall.cmd`** (or press *Remove SpeedWatch* in the panel). It
   deletes the scheduled task and the desktop shortcut, and asks whether to delete your
   recorded results too.
2. **Delete the SpeedWatch folder.**

Nothing else is left behind, with one optional extra: if the installer had to get the
Ookla Speedtest tool through `winget`, that tool stays installed. Remove it too with
`winget uninstall Ookla.Speedtest.CLI`, or from *Settings → Apps*.

More detail on both is further down.

---

## A word about the unit, because it causes more arguments than anything else

Internet plans and speed tests are measured in **Mb/s — megabits per second**.
File downloads in a browser are shown in **MB/s — megabytes per second**.
**One byte is eight bits**, so the two differ by a factor of eight:

| Speed test says | Browser download shows |
|---|---|
| 1000 Mb/s | 125 MB/s |
| 100 Mb/s | 12.5 MB/s |
| 44 Mb/s | 5.5 MB/s |
| 8 Mb/s | 1 MB/s |

A plan advertised as "1000 megas", "1 Gbps" or "1000 Mb" is **1000 Mb/s**. That is
the number to enter in the panel. Getting this wrong by a factor of eight is
the single easiest way to either panic over nothing or let a real fault slide, so
SpeedWatch now shows both units side by side everywhere it shows a speed.

---

## Setup in detail

Requirements: Windows 10 or 11, an internet connection during setup. Everything else
(Windows PowerShell 5.1, Task Scheduler) is already part of Windows.

1. Put this folder wherever you want it to live. Where you put it *is* where it is
   installed; there is no second copy anywhere.
2. Double-click **`Install.cmd`**.
3. Double-click **`SpeedWatch.cmd`** (or the desktop shortcut it creates).
4. In the panel, enter your plan's **download** speed in Mb/s (and its upload
   speed, if you know it) and press *Save*. Until you do, readings are recorded
   but not coloured, because there is nothing to compare them against.

If you received SpeedWatch as a zip by email or download, you can extract it
normally — the installer clears Windows' "downloaded from the internet" mark on
its own files, so the background tests never stop to ask for permission.

No administrator rights are needed. If Windows SmartScreen warns about the `.cmd`
file, choose *More info -> Run anyway* — it is a text file you can read in Notepad.

The installer needs the Ookla Speedtest CLI. It tries `winget` first, then a direct
download from Ookla. If both fail it says so, and you can install it yourself:

```
winget install Ookla.Speedtest.CLI
```

### Setting the plan and the times from the installer

```
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -PlanMbps 300 -PlanUpMbps 30 -Times 09:30,14:00,21:00
```

Both are optional. Re-running replaces the existing task rather than adding a
second one.

## Test times

SpeedWatch runs one test at each time you list. **Add and remove times from the
panel** — type `HH:MM` in 24-hour form and press *Add*, or press the `x` on a time
to drop it. Changes take effect immediately, and a task that is switched **off**
stays off when you edit the schedule.

More times a day gives a better picture: speeds often vary between quiet hours and
peak evening use, and a single daily reading cannot tell a stable connection from
one that degrades every night. Three or four is plenty — each test moves real data.

The times also live in `settings.json` if you prefer editing them there; the panel
and the installer read the same file.

---

## Settings

Everything you might want to change lives in `settings.json`. The panel edits the
first three; the rest are for people who want to tune things by hand.

| Setting | Meaning | Default |
|---|---|---|
| `planMbps` | Download speed your plan is sold at, **Mb/s** | *(none - set it in the panel)* |
| `planUpMbps` | Upload speed of your plan, Mb/s. Optional; when set, upload is coloured too | *(none)* |
| `times` | When to test, 24-hour `HH:MM` | `["14:00"]` |
| `bands` | Where the colours change, as % of plan: under the 1st red, then yellow, white, and green from the 3rd up | `[25, 50, 75]` |
| `retries` | Ookla attempts before falling back to Cloudflare (1-5) | `3` |
| `retryDelaySeconds` | Wait between those attempts (10-120) | `45` |
| `reportDays` | How many days back the report opens on the first time; `0` = everything | `30` |

Out-of-range or malformed values fall back to the default rather than breaking
anything. Each reading also records the plan in force when it was taken, so
changing your plan later does not recolour your history.

## The report

Choose how far back to look with the bar at the top: 7, 14, 30 or 90 days, all
time, or type any number of days. Everything below follows it: the charts, the
averages and counts, and the table. "Latest reading" always shows the newest
test. The report remembers the range you last picked; the very first time it opens
on `reportDays` from `settings.json`. Adding `#days=60` (or `#days=all`) to the
report's address opens that range directly, so a view can be bookmarked.

Each test is one bar, coloured by its share of your plan, with lines where the
colours change and a line at 100% of plan. Failed tests are marked with `x` on
the baseline rather than left out — a test that could not run is information too.
When a range holds more tests than the chart can draw legibly (a long range, or a
narrow window), it switches to one bar per day showing that day's middle value;
hover a bar to see the day's lowest and highest readings as well. Upload and
latency get their own charts, and every reading in the range is listed underneath
with a link to its speedtest.net result.

---

## How it works

**Nothing runs in the background.** No service, no tray icon, no startup entry, no
resident process. The schedule is a single **Windows Task Scheduler** entry that
launches a script, which takes one reading, writes one line to a file, and exits.
Between runs SpeedWatch uses no RAM and no CPU, because no process exists.

You can see the entry yourself: Task Scheduler -> Task Scheduler Library -> **SpeedWatch**.

**Missed runs are caught up.** The task is registered with *Start when available*,
so if the PC is off, asleep, or you are not logged in at the scheduled time, Windows
runs it as soon as the machine is back. If SpeedWatch was switched **off** at that
time and you switch it on later the same day, the panel takes the reading immediately.

**Two measurement engines.** Ookla's Speedtest CLI runs first — it produces a
`speedtest.net/result/...` URL and the shareable result card, which is the artifact
an ISP will ask for. If Ookla is unreachable (their config endpoint returns 5xx more
often than you would think), it falls back to **Cloudflare**: timed transfers against
`speed.cloudflare.com`. A day is only recorded as failed when both are unreachable,
which is itself a meaningful result. Every record states which engine produced it,
and the report labels each row, because the two measure the same line by different
methods and should not be compared blindly.

**Why the CLI and not the website.** Same company, same servers, same Results
history — but about 20 MB of RAM for thirty seconds, instead of driving a headless
browser.

---

## The panel

| Control | What it does |
|---|---|
| **ON / OFF** | Enables or disables the scheduled task. Off means no tests at all. |
| **Run now** | Takes a reading immediately, without touching the schedule. |
| **Open report** | Opens the report page in your browser. |
| **Open folder** | Opens this folder in Explorer. |
| **Remove SpeedWatch** | Runs the uninstaller. |

Closing the panel leaves nothing running.

---

## Where things are

```
SpeedWatch\
  settings.json          plan speeds, test times, colour bands, retries
  Install.cmd            setup
  SpeedWatch.cmd         opens the panel
  Uninstall.cmd          removes the scheduled task and shortcut
  report\report.html     the report (opens straight from disk)
  scripts\               the scripts, all plain text
  bin\                   speedtest.exe, if it was downloaded here
  data\
    history.ndjson       one line of JSON per reading - the real record
    history.js           the same data, for the report page
    images\              the speedtest.net result card for each run
    speedwatch.log       last 500 log lines, trimmed automatically
```

The report opens as a local file and loads nothing from the internet — no fonts, no
scripts, no tracking. That is deliberate: it has to work during an outage.

---

## Resource use

- **Between runs:** nothing. No process exists.
- **During a run:** roughly 30–40 seconds, ~20 MB RAM, one short CPU burst. Longer
  if it has to retry or fall back.
- **Data per run:** a speed test moves real traffic — a few hundred MB on a fast
  line, far less on a slow one. This is why a few tests a day is plenty, and hourly is not a good idea.
- **Disk growth:** about 400 bytes of JSON plus a ~60 KB image per day — under
  25 MB a year. The log trims itself; the report reads the most recent 400 runs.

---

## Removing it completely

1. Run **`Uninstall.cmd`** (or press *Remove SpeedWatch* in the panel). It deletes the
   scheduled task and the desktop shortcut, and asks whether to delete your results.
2. Delete this folder.

That is SpeedWatch's whole footprint. It writes nothing to the registry, to
`Program Files`, or to your startup items.

The one thing it does not remove is the Ookla Speedtest CLI **if** the installer got it
through `winget` (it then lives where winget keeps its apps, not in this folder). It is a
separate, ordinary app that does nothing unless something runs it. To remove it as well:

```
winget uninstall Ookla.Speedtest.CLI
```

If the installer downloaded it directly instead, it is in this folder's `bin\` and goes
when you delete the folder.

---

## If something goes wrong

- **Panel will not open** — run `powershell -ExecutionPolicy Bypass -STA -File scripts\panel.ps1`
  from the folder to see the error.
- **Tests are not running** — open `data\speedwatch.log`, and check the task's
  *Last Run Result* in Task Scheduler.
- **"Speedtest CLI not found"** — install it with winget as above, then re-run `Install.cmd`.
- **Antivirus removes the scripts** — they are plain text; read them. SpeedWatch does
  not hide windows using techniques that resemble evasion, and it ships no compiled
  binary of its own. The only executable is Ookla's `speedtest.exe`.
