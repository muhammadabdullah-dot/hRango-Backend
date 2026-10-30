"""Demo data part: work. Project management (three workspaces with folders, sprints, tasks and all the
collaboration around them), engagement (newsfeed, announcements, surveys) and custom forms for Top Edge
Technologies, each action done by the person who would do it. Needs only scripts.demo (the people); the
other parts may run before it."""
import time

from scripts.demo_data import World, _work_engagement, _work_forms, _work_pm


def seed(w: World) -> None:
    started = time.perf_counter()
    for label, part in (("projects", _work_pm), ("engagement", _work_engagement), ("custom forms", _work_forms)):
        t0 = time.perf_counter()
        counts = part.seed(w)
        made = ", ".join(f"{v} {k.replace('_', ' ')}" for k, v in counts.items())
        print(f"  {label}: {made} ({time.perf_counter() - t0:.0f}s)")
    print(f"  work done in {time.perf_counter() - started:.0f}s")
