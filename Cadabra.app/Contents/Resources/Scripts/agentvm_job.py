#!/usr/bin/env python3
"""Run a long agent-vm command as a detached job that outlives the window and Cadabra.

Image builds take minutes to an hour, box starts half a minute. A window handler cannot wait
for them, and closing the window or quitting Cadabra must not end them. So the Box Manager
starts them here: each job runs in its own session, away from the handler, and records what
happened in its own folder, which any later handler (or the next launch) reads.

A job's folder, JOBS_DIR/<id>/ (JOBS_DIR is ~/Library/Application Support/Cadabra/Jobs):
    job.json   kind, target, title, argv, started: written once, before the job runs
    pid        the runner's pid (the process that waits for agent-vm and forwards Cancel)
    lock       held by the runner for as long as it lives: THE test of "still running"
    log        agent-vm's stderr: JSON progress events under --json, then maybe "Error: ..."
    out        agent-vm's stdout
    canceled   present once Cancel was asked for
    exit       agent-vm's exit status, written atomically when it ends; its time is the end

Why a lock and not a pid check: a pid can be reused once its process is gone, and a check of a
reused pid's command line is a guess. An flock is released by the kernel when its holder dies,
however it dies, so "someone holds the lock" is exactly "the runner is alive", and while it is
alive its pid cannot be reused, which makes signaling the recorded pid safe.

Usage:
    agentvm_job.py start JOBS_DIR KIND TARGET TITLE -- COMMAND...
        Starts the job and prints its id. Exits 3, printing why on stderr, when a job with the
        same TARGET still runs (two starts of one box, a delete during a guest update).
    agentvm_job.py list JOBS_DIR
        One row per job, oldest first (tab-separated, the invariant of agentvm_json.py):
            id, kind, target, title, state, status, started, ended, step, fraction, message,
            notice, error
        state: running, done, failed, canceled, or lost (the runner died without recording a
        result). status is agent-vm's exit status. step, fraction and message come from the
        last progress event, notice from the last notice; error is the first line of the
        error of a failed or lost job. Finished jobs that ended over a week ago are removed.
    agentvm_job.py error JOBS_DIR ID
        The whole error of a finished job, as agent-vm wrote it.
    agentvm_job.py cancel JOBS_DIR ID
        Asks a running job to stop: SIGINT to the runner, which passes it to agent-vm. agent-vm
        stops at the next safe point and exits 130. Exits 1 when the job is not running.
    agentvm_job.py forget JOBS_DIR ID
        Removes a job that no longer runs. Exits 1 when it still runs.
    agentvm_job.py run JOBS_DIR ID LOCK_FD
        Internal: the detached runner that start execs. Its command line is what the orphan
        reaper in aichat.server.library.sh recognizes and leaves alone.
"""
import errno
import fcntl
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import time

# Python caches this import's bytecode under PYTHONPYCACHEPREFIX, which OMC sets for every
# handler (and omctest for every test), and which the detached runner inherits. So nothing is
# written inside the signed application.
from agentvm_json import log_error, log_progress, row

ID_PATTERN = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$")
KEEP_SECONDS = 7 * 24 * 3600
LOST_ERROR = "The job ended without recording a result: its runner was stopped."


class Refusal(Exception):
    """A request this job store turns down, with the reason for the user."""

    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


def job_dir(jobs, job_id):
    if not ID_PATTERN.fullmatch(job_id):
        raise Refusal(f"{job_id!r} is not a job id")
    path = os.path.join(jobs, job_id)
    if not os.path.isfile(os.path.join(path, "job.json")):
        raise Refusal(f"there is no job {job_id}")
    return path


def write_atomically(path, text):
    temporary = f"{path}.{os.getpid()}.tmp"
    with open(temporary, "w", encoding="utf-8") as out:
        out.write(text)
    os.replace(temporary, path)


def read_text(path):
    try:
        with open(path, encoding="utf-8") as source:
            return source.read().strip()
    except OSError:
        return None


class DirectoryLock:
    """The jobs folder's own lock: job creation and listing never see each other half done."""

    def __init__(self, jobs):
        self.path = os.path.join(jobs, ".lock")

    def __enter__(self):
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_):
        os.close(self.fd)


def runner_alive(path):
    """True while the job's runner holds its lock. The probe asks for a SHARED lock, which
    only the runner's exclusive one refuses: two probes at once (a list during a cancel) must
    not take each other for a live runner, or cancel would signal a dead runner's pid."""
    try:
        fd = os.open(os.path.join(path, "lock"), os.O_RDONLY)
    except OSError:
        return False
    try:
        fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except OSError as problem:
        if problem.errno in (errno.EWOULDBLOCK, errno.EAGAIN):
            return True
        raise
    finally:
        os.close(fd)
    return False


def job_state(path):
    """(state, status, ended): ended is a Unix time, or None while the job runs."""
    exit_path = os.path.join(path, "exit")
    text = read_text(exit_path)
    if text is not None:
        try:
            status = int(text)
        except ValueError:
            status = None
        ended = os.path.getmtime(exit_path)
        if status == 0:
            return "done", status, ended
        if os.path.exists(os.path.join(path, "canceled")):
            return "canceled", status, ended
        return "failed", status, ended
    if runner_alive(path):
        return "running", None, None
    newest = [os.path.getmtime(os.path.join(path, name))
              for name in ("job.json", "pid", "log") if os.path.exists(os.path.join(path, name))]
    return "lost", None, max(newest) if newest else time.time()


def iso(moment):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(moment)) if moment else None


def load_job(path):
    try:
        with open(os.path.join(path, "job.json"), encoding="utf-8") as source:
            job = json.load(source)
    except (OSError, ValueError):
        return None
    return job if isinstance(job, dict) else None


def job_ids(jobs):
    try:
        names = os.listdir(jobs)
    except FileNotFoundError:
        return []
    return sorted(name for name in names if ID_PATTERN.fullmatch(name))


# -- start ---------------------------------------------------------------------------------

def start(jobs, kind, target, title, argv):
    for value, what in ((kind, "kind"), (target, "target"), (title, "title")):
        if not value or any(ch in value for ch in "\t\r\n"):
            raise Refusal(f"the job's {what} must be one line of text", 2)
    if not argv or not os.path.isabs(argv[0]):
        raise Refusal("the job's command must start with an absolute path", 2)
    if not os.path.isabs(jobs):
        raise Refusal("the jobs folder must be an absolute path", 2)
    os.makedirs(jobs, mode=0o700, exist_ok=True)
    with DirectoryLock(jobs):
        for job_id in job_ids(jobs):
            path = os.path.join(jobs, job_id)
            job = load_job(path)
            if job and job.get("target") == target and job_state(path)[0] == "running":
                raise Refusal(f"{job.get('title') or 'Another job'} is still running for "
                              f"{target.split(':', 1)[-1]}. Wait for it to finish, or cancel it.", 3)
        while True:
            job_id = time.strftime("%Y%m%d-%H%M%S-", time.gmtime()) + secrets.token_hex(3)
            path = os.path.join(jobs, job_id)
            try:
                os.mkdir(path, 0o700)
                break
            except FileExistsError:
                continue
        write_atomically(os.path.join(path, "job.json"),
                         json.dumps({"kind": kind, "target": target, "title": title,
                                     "argv": argv, "started": iso(time.time())}, indent=2) + "\n")
        # Taken here and handed down to the runner, so the job counts as running from the moment
        # it exists: a list between now and the runner's first step never calls it lost.
        lock_fd = os.open(os.path.join(path, "lock"), os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        sys.stdout.flush()
        sys.stderr.flush()
        child = os.fork()
        if child == 0:
            detach_and_run(jobs, job_id, lock_fd)
        os.waitpid(child, 0)
        os.close(lock_fd)
    print(job_id)
    return 0


def detach_and_run(jobs, job_id, lock_fd):
    """In the forked child: leave the caller's session, fork once more, exec the runner.
    Never returns."""
    try:
        os.setsid()
        if os.fork() != 0:
            os._exit(0)
        # The handler reads start's stdout through $( ), which waits until every copy of that
        # pipe is closed; the runner must hold none of it.
        null = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(null, fd)
        if null > 2:
            os.close(null)
        # Every other descriptor is closed, found in /dev/fd. The descriptor limit is no bound
        # to count up to: when it is "unlimited", SC_OPEN_MAX is LONG_MAX, which os.closerange
        # refuses (OverflowError), and the job would be lost before its runner started.
        try:
            open_fds = [int(name) for name in os.listdir("/dev/fd")]
        except (OSError, ValueError):
            open_fds = range(3, 1 << 16)
        for fd in open_fds:
            if fd > 2 and fd != lock_fd:
                try:
                    os.close(fd)
                except OSError:
                    pass
        os.set_inheritable(lock_fd, True)
        os.chdir("/")
        script = os.path.abspath(__file__)
        os.execv(sys.executable, [sys.executable, script, "run", jobs, job_id, str(lock_fd)])
    finally:
        os._exit(127)


# -- run -----------------------------------------------------------------------------------

def run(jobs, job_id, lock_fd):
    path = os.path.join(jobs, job_id)
    job = load_job(path) or {}
    argv = job.get("argv")
    exit_path = os.path.join(path, "exit")
    canceled_path = os.path.join(path, "canceled")
    running = []

    # Cancel (SIGINT from `cancel`) or a system shutdown (SIGTERM) is passed on to agent-vm,
    # which stops at its next safe point; the runner itself keeps waiting to record the result.
    def forward(signum, _frame):
        open(canceled_path, "a").close()
        for child in running:
            try:
                child.send_signal(signum)
            except OSError:
                pass

    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)
    write_atomically(os.path.join(path, "pid"), f"{os.getpid()}\n")
    with open(os.path.join(path, "log"), "ab") as log, open(os.path.join(path, "out"), "ab") as out:
        if not isinstance(argv, list) or not argv:
            log.write(b"Error: the job has no command to run\n")
            write_atomically(exit_path, "127\n")
            return 127
        try:
            child = subprocess.Popen([str(arg) for arg in argv], stdin=subprocess.DEVNULL,
                                     stdout=out, stderr=log, cwd="/", close_fds=True)
        except OSError as problem:
            log.write(f"Error: could not run {argv[0]}: {problem.strerror}\n".encode())
            write_atomically(exit_path, "127\n")
            return 127
        running.append(child)
        if os.path.exists(canceled_path):
            # Canceled before agent-vm existed to hear it.
            child.send_signal(signal.SIGINT)
        status = child.wait()
    if status < 0:
        status = 128 - status
    write_atomically(exit_path, f"{status}\n")
    os.close(lock_fd)
    return 0


# -- list, error, cancel, forget -----------------------------------------------------------

def list_jobs(jobs):
    rows = []
    if not os.path.isdir(jobs):
        return rows
    now = time.time()
    with DirectoryLock(jobs):
        for job_id in job_ids(jobs):
            path = os.path.join(jobs, job_id)
            job = load_job(path)
            if job is None:
                # A start that died between creating the folder and writing job.json. Never
                # listed; removed once it is clearly not a start still in progress.
                try:
                    if now - os.path.getmtime(path) > 3600:
                        shutil.rmtree(path, ignore_errors=True)
                except OSError:
                    pass
                continue
            state, status, ended = job_state(path)
            if ended is not None and now - ended > KEEP_SECONDS:
                shutil.rmtree(path, ignore_errors=True)
                continue
            log = os.path.join(path, "log")
            progress = log_progress(log) if os.path.exists(log) else [None] * 4
            error = None
            if state in ("failed", "lost"):
                error = (log_error(log) if os.path.exists(log) else "") or \
                        (LOST_ERROR if state == "lost" else None)
                error = error.splitlines()[0] if error else None
            rows.append(row([job_id, job.get("kind"), job.get("target"), job.get("title"),
                             state, status, job.get("started"), iso(ended)] + progress + [error]))
    return rows


def error_of(jobs, job_id):
    path = job_dir(jobs, job_id)
    state, status, _ = job_state(path)
    log = os.path.join(path, "log")
    text = log_error(log) if os.path.exists(log) else ""
    if not text and state == "lost":
        text = LOST_ERROR
    if not text and state == "failed":
        text = f"agent-vm failed (status {status}) and gave no reason."
    return text


def cancel(jobs, job_id):
    path = job_dir(jobs, job_id)
    if job_state(path)[0] != "running":
        raise Refusal("the job is not running")
    pid_text = read_text(os.path.join(path, "pid"))
    if not pid_text or not pid_text.isdigit():
        raise Refusal("the job has not started yet; try again in a moment")
    # Checked once more right before the signal: the runner holds the lock, so it is alive and
    # its pid is still its own. The runner marks the job canceled when the signal arrives.
    if not runner_alive(path):
        raise Refusal("the job is not running")
    os.kill(int(pid_text), signal.SIGINT)
    return 0


def forget(jobs, job_id):
    path = job_dir(jobs, job_id)
    with DirectoryLock(jobs):
        if job_state(path)[0] == "running":
            raise Refusal("the job is still running; cancel it first")
        shutil.rmtree(path)
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    try:
        if command == "start" and len(argv) >= 8 and argv[6] == "--":
            return start(argv[2], argv[3], argv[4], argv[5], argv[7:])
        if command == "run" and len(argv) == 5 and argv[4].isdigit():
            return run(argv[2], argv[3], int(argv[4]))
        if command == "list" and len(argv) == 3:
            for line in list_jobs(argv[2]):
                sys.stdout.write(line + "\n")
            return 0
        if command == "error" and len(argv) == 4:
            text = error_of(argv[2], argv[3])
            if text:
                sys.stdout.write(text + "\n")
            return 0
        if command == "cancel" and len(argv) == 4:
            return cancel(argv[2], argv[3])
        if command == "forget" and len(argv) == 4:
            return forget(argv[2], argv[3])
    except Refusal as refusal:
        sys.stderr.write(f"{refusal}\n")
        return refusal.status
    except OSError as problem:
        sys.stderr.write(f"agentvm_job.py {command}: {problem}\n")
        return 1
    sys.stderr.write(__doc__.split("Usage:", 1)[1])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
