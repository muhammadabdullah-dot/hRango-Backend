"""Spreads the demo's history over past weeks. The API stamps everything with the time of the call, as it should for
real use, so a demo made in one go would chart it all on one day. Only this demo script writes these dates."""
from app.core.db import connect
from scripts.demo_data import World


def seed(w: World) -> None:
    conn = connect()
    cur = conn.cursor()
    today = w.today.isoformat()
    # Closed tasks: on or before their due date, or after it when they were closed late.
    tasks = cur.execute("""
        UPDATE t SET closed_at = DATEADD(DAY, -(ABS(CHECKSUM(t.id)) % 21), CAST(? AS DATETIME2(0)))
        FROM pm.task t WHERE t.closed_at IS NOT NULL AND t.is_closed_late = 0""", today).rowcount
    # Hiring stages: spread from each application's date up to today.
    stages = cur.execute("""
        UPDATE h SET changed_at = DATEADD(DAY, ABS(CHECKSUM(h.id)) % (DATEDIFF(DAY, a.applied_on, ?) + 1),
                                          CAST(a.applied_on AS DATETIME2(0)))
        FROM rec.application_stage_history h JOIN rec.application a ON a.id = h.application_id
        WHERE a.applied_on < ?""", today, today).rowcount
    # Newsfeed: newest post stays recent, the rest go back up to five weeks.
    posts = cur.execute("""
        UPDATE p SET created_at = DATEADD(DAY, -(ABS(CHECKSUM(p.id)) % 35), p.created_at) FROM eng.post p""").rowcount
    conn.commit()
    conn.close()
    print(f"  backdate: {tasks} closed tasks, {stages} hiring stages, {posts} posts spread over past weeks")
