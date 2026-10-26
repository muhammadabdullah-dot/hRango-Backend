"""Engagement newsfeed: posts with photos, audiences, reactions, comments with replies and likes,
views, My Posts, moderation (pin, hide, delete), settings, notifications and events."""
import pytest

from tests import factories
from tests import factories_engagement as fe

API = fe.API


@pytest.fixture(scope="module")
def world(db, client):
    """A company of its own (settings change here): two departments, one with a sub-department, two branches."""
    company = factories.company(db)
    admin = factories.login_as(db, client, company, role_codes="company_admin")
    sales = factories.department(db, company, name=f"Sales {factories.tag()}")
    south = factories.department(db, company, name=f"Sales South {factories.tag()}", parent_id=sales)
    tech = factories.department(db, company, name=f"Tech {factories.tag()}")
    north = factories.branch(db, company)
    karachi = factories.branch(db, company)
    people = {
        "author": fe.person(db, client, company, sales, north, first_name="Ayesha"),
        "colleague": fe.person(db, client, company, sales, karachi, first_name="Bilal"),
        "junior": fe.person(db, client, company, south, karachi, first_name="Danish"),
        "outsider": fe.person(db, client, company, tech, karachi, first_name="Farah"),
        "neighbour": fe.person(db, client, company, tech, north, first_name="Hamza"),
    }
    return {"company": company, "admin": admin, "sales": sales, "south": south, "tech": tech, "north": north,
            "karachi": karachi, **people}


def _feed_ids(client, headers, **params) -> list[str]:
    r = client.get(f"{API}/posts", params={"pageSize": 100, **params}, headers=headers)
    assert r.status_code == 200, r.text
    return [p["id"] for p in r.json()["data"]]


def test_post_with_two_photos(db, client, world):
    author, colleague = world["author"], world["colleague"]
    one, two = fe.photo(client, author["headers"], "team.png"), fe.photo(client, author["headers"], "office.png")
    pdf = factories.upload(client, author["headers"], module="engagement")

    refused = client.post(f"{API}/posts", json={"body": "Minutes", "mediaFileIds": [pdf["id"]]}, headers=author["headers"])
    assert refused.status_code == 422 and "mediaFileIds" in refused.json()["fieldErrors"]
    empty = client.post(f"{API}/posts", json={"body": "  "}, headers=author["headers"])
    assert empty.status_code == 422 and "body" in empty.json()["fieldErrors"]

    p = fe.post(client, author["headers"], "Our team at the annual dinner", mediaFileIds=[one["id"], two["id"]])
    assert p["visibility"] == "public" and p["isMine"] is True and p["authorName"].startswith("Ayesha")
    assert [m["name"] for m in p["media"]] == ["team.png", "office.png"]
    assert all(m["mediaType"] == "photo" and m["url"].startswith(f"/api/files/{m['fileId']}/download?token=")
               for m in p["media"])
    assert p["link"] == f"/engagement/posts/{p['id']}"
    assert p["reactionCount"] == 0 and p["commentCount"] == 0 and p["viewCount"] == 0

    # The signed photo link works without signing in.
    assert client.get(p["media"][0]["url"]).status_code == 200

    seen = client.get(f"{API}/posts/{p['id']}", headers=colleague["headers"]).json()["data"]
    assert seen["isMine"] is False and len(seen["media"]) == 2
    assert fe.events(db, "engagement.post_published", p["id"]) == 1

    # Media-only posts are fine; another company's file is not.
    assert fe.post(client, author["headers"], None, mediaFileIds=[one["id"]])["body"] is None
    other_company = factories.company(db)
    stranger = factories.login_as(db, client, other_company, role_codes="company_admin")
    foreign = fe.photo(client, stranger["headers"])
    bad = client.post(f"{API}/posts", json={"body": "x", "mediaFileIds": [foreign["id"]]}, headers=author["headers"])
    assert bad.status_code == 422


def test_audiences(db, client, world):
    author, colleague, junior = world["author"], world["colleague"], world["junior"]
    outsider, neighbour, admin = world["outsider"], world["neighbour"], world["admin"]

    dept = fe.post(client, author["headers"], "Sales targets for the quarter", visibility="department")
    assert dept["departmentId"] == str(world["sales"]) and dept["departmentName"].startswith("Sales")
    branch = fe.post(client, author["headers"], "North office closes early", visibility="branch")
    assert branch["branchId"] == str(world["north"])

    assert dept["id"] in _feed_ids(client, colleague["headers"])
    assert dept["id"] in _feed_ids(client, junior["headers"])          # sub-department
    assert dept["id"] not in _feed_ids(client, outsider["headers"])
    assert client.get(f"{API}/posts/{dept['id']}", headers=outsider["headers"]).status_code == 404
    assert dept["id"] in _feed_ids(client, admin["headers"])            # moderators see every post

    assert branch["id"] in _feed_ids(client, neighbour["headers"])      # same branch, other department
    assert branch["id"] not in _feed_ids(client, colleague["headers"])

    # Staff post only to their own department (or one above it) and branch.
    other = client.post(f"{API}/posts", json={"body": "Hi Tech", "visibility": "department",
                                              "departmentId": str(world["tech"])}, headers=author["headers"])
    assert other.status_code == 403
    up = client.post(f"{API}/posts", json={"body": "Hi all Sales", "visibility": "department",
                                           "departmentId": str(world["sales"])}, headers=junior["headers"])
    assert up.status_code == 201
    # Mentioning someone who will not see the post is refused.
    hidden_from = client.post(f"{API}/posts", json={"body": "@Farah look", "visibility": "department",
                                                    "mentionIds": [str(outsider["employee_id"])]},
                              headers=author["headers"])
    assert hidden_from.status_code == 422 and "mentionIds" in hidden_from.json()["fieldErrors"]


def test_reactions_comments_and_notifications(db, client, world):
    author, colleague, junior = world["author"], world["colleague"], world["junior"]
    p = fe.post(client, author["headers"], "We hit our target!", mentionIds=[str(junior["employee_id"])])
    assert [m["employeeId"] for m in p["mentions"]] == [str(junior["employee_id"])]
    assert fe.notifications(db, junior["employee_id"], "eng.post", p["id"]) == 1

    # Reactions: one per person; a new one tells the author, a change or the author's own does not.
    liked = client.put(f"{API}/posts/{p['id']}/reaction", json={"kind": "like"}, headers=colleague["headers"])
    assert liked.status_code == 200, liked.text
    assert liked.json()["data"]["myReaction"] == "like" and liked.json()["data"]["reactionCount"] == 1
    loved = client.put(f"{API}/posts/{p['id']}/reaction", json={"kind": "love"}, headers=colleague["headers"])
    assert loved.json()["data"]["reactionCount"] == 1 and loved.json()["data"]["reactions"] == [{"kind": "love", "count": 1}]
    client.put(f"{API}/posts/{p['id']}/reaction", json={"kind": "celebrate"}, headers=author["headers"])
    assert client.put(f"{API}/posts/{p['id']}/reaction", json={"kind": "angry"},
                      headers=junior["headers"]).status_code == 422
    assert fe.notifications(db, author["employee_id"], "eng.post", p["id"]) == 1
    reactors = client.get(f"{API}/posts/{p['id']}/reactions", headers=junior["headers"]).json()
    assert reactors["meta"]["total"] == 2
    assert {r["kind"] for r in reactors["data"]} == {"love", "celebrate"}
    assert client.get(f"{API}/posts/{p['id']}/reactions", params={"kind": "love"},
                      headers=junior["headers"]).json()["meta"]["total"] == 1

    # Comments, replies (a reply to a reply joins the thread), likes, mentions.
    c1 = client.post(f"{API}/posts/{p['id']}/comments", json={"body": "Congratulations!"}, headers=colleague["headers"])
    assert c1.status_code == 201, c1.text
    top = c1.json()["data"]
    assert fe.notifications(db, author["employee_id"], "eng.post", p["id"]) == 2
    assert fe.events(db, "engagement.comment_added", top["id"]) == 1
    reply = client.post(f"{API}/posts/{p['id']}/comments", json={"body": "Thank you", "parentId": top["id"]},
                        headers=author["headers"]).json()["data"]
    assert reply["parentId"] == top["id"]
    assert fe.notifications(db, colleague["employee_id"], "eng.post", p["id"]) == 1     # "replied to your comment"
    deep = client.post(f"{API}/posts/{p['id']}/comments",
                       json={"body": "Well done @Bilal", "parentId": reply["id"],
                             "mentionIds": [str(colleague["employee_id"])]}, headers=junior["headers"]).json()["data"]
    assert deep["parentId"] == top["id"] and deep["mentions"][0]["employeeId"] == str(colleague["employee_id"])
    # Danish replied to Ayesha's reply (Ayesha is told) and mentioned Bilal (Bilal is told of the mention).
    assert fe.notifications(db, colleague["employee_id"], "eng.post", p["id"]) == 2

    like = client.put(f"{API}/comments/{top['id']}/like", json={"liked": True}, headers=author["headers"])
    assert like.json()["data"]["likeCount"] == 1 and like.json()["data"]["likedByMe"] is True
    client.put(f"{API}/comments/{top['id']}/like", json={"liked": True}, headers=author["headers"])  # once
    assert fe.notifications(db, colleague["employee_id"], "eng.post", p["id"]) == 3
    own_like = client.put(f"{API}/comments/{top['id']}/like", json={"liked": True}, headers=colleague["headers"])
    assert own_like.json()["data"]["likeCount"] == 2
    assert fe.notifications(db, colleague["employee_id"], "eng.post", p["id"]) == 3
    unliked = client.put(f"{API}/comments/{top['id']}/like", json={"liked": False}, headers=colleague["headers"])
    assert unliked.json()["data"]["likeCount"] == 1 and unliked.json()["data"]["likedByMe"] is False

    threads = client.get(f"{API}/posts/{p['id']}/comments", headers=world["neighbour"]["headers"]).json()
    assert threads["meta"]["total"] == 1
    thread = threads["data"][0]
    assert thread["body"] == "Congratulations!" and thread["replyCount"] == 2
    assert [r["body"] for r in thread["replies"]] == ["Thank you", "Well done @Bilal"]
    got = client.get(f"{API}/posts/{p['id']}", headers=world["neighbour"]["headers"]).json()["data"]
    assert got["commentCount"] == 3 and got["reactionCount"] == 2 and got["myReaction"] is None

    # Every notification is also an event.
    assert fe.scalar(db, "SELECT COUNT(*) FROM core.outbox_event WHERE event_type = N'notification.created' "
                         "AND JSON_VALUE(payload, '$.entityId') = ?", p["id"]) >= 5


def test_views_counted_once(db, client, world):
    author, colleague, junior = world["author"], world["colleague"], world["junior"]
    p = fe.post(client, author["headers"], "Read me")
    first = client.post(f"{API}/posts/{p['id']}/view", headers=colleague["headers"]).json()["data"]
    assert first == {"id": p["id"], "viewCount": 1, "counted": True}
    again = client.post(f"{API}/posts/{p['id']}/view", headers=colleague["headers"]).json()["data"]
    assert again["viewCount"] == 1 and again["counted"] is False
    assert client.post(f"{API}/posts/{p['id']}/view", headers=author["headers"]).json()["data"]["viewCount"] == 1
    client.post(f"{API}/posts/{p['id']}/view", headers=junior["headers"])
    assert client.get(f"{API}/posts/{p['id']}", headers=author["headers"]).json()["data"]["viewCount"] == 2


def test_edit_and_delete_own_vs_moderator(db, client, world):
    author, colleague, admin = world["author"], world["colleague"], world["admin"]
    p = fe.post(client, author["headers"], "Frist draft")
    body = {"body": "First draft", "rowVersion": p["rowVersion"]}
    assert client.put(f"{API}/posts/{p['id']}", json=body, headers=colleague["headers"]).status_code == 403
    edited = client.put(f"{API}/posts/{p['id']}", json=body, headers=author["headers"])
    assert edited.status_code == 200 and edited.json()["data"]["editedAt"] and edited.json()["data"]["body"] == "First draft"
    assert client.put(f"{API}/posts/{p['id']}", json=body, headers=author["headers"]).status_code == 409   # stale
    assert client.put(f"{API}/posts/{p['id']}", json={"body": "x"}, headers=author["headers"]).status_code == 422

    c = client.post(f"{API}/posts/{p['id']}/comments", json={"body": "Typo in the title"},
                    headers=colleague["headers"]).json()["data"]
    assert client.put(f"{API}/comments/{c['id']}", json={"body": "No", "rowVersion": c["rowVersion"]},
                      headers=author["headers"]).status_code == 403
    ce = client.put(f"{API}/comments/{c['id']}", json={"body": "Typo fixed now", "rowVersion": c["rowVersion"]},
                    headers=colleague["headers"])
    assert ce.status_code == 200 and ce.json()["data"]["editedAt"]
    assert client.put(f"{API}/comments/{c['id']}", json={"body": "Again", "rowVersion": c["rowVersion"]},
                      headers=colleague["headers"]).status_code == 409
    # The post's author does not delete other people's comments; a moderator does.
    rv = ce.json()["data"]["rowVersion"]
    assert client.delete(f"{API}/comments/{c['id']}", params={"rowVersion": rv}, headers=author["headers"]).status_code == 403
    assert client.delete(f"{API}/comments/{c['id']}", params={"rowVersion": rv}, headers=admin["headers"]).status_code == 204

    current = edited.json()["data"]
    assert client.delete(f"{API}/posts/{p['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=colleague["headers"]).status_code == 403
    assert client.delete(f"{API}/posts/{p['id']}", params={"rowVersion": p["rowVersion"]},
                         headers=author["headers"]).status_code == 409
    assert client.delete(f"{API}/posts/{p['id']}", params={"rowVersion": current["rowVersion"]},
                         headers=author["headers"]).status_code == 204
    assert client.get(f"{API}/posts/{p['id']}", headers=author["headers"]).status_code == 404
    mine = client.get(f"{API}/my-posts", params={"pageSize": 100}, headers=author["headers"]).json()["data"]
    assert p["id"] not in [x["id"] for x in mine] and all(x["isMine"] for x in mine)
    assert fe.events(db, "engagement.post_deleted", p["id"]) == 1

    # A moderator deletes someone else's post; the author is told.
    q = fe.post(client, colleague["headers"], "Off-topic advert")
    assert client.delete(f"{API}/posts/{q['id']}", params={"rowVersion": q["rowVersion"]},
                         headers=admin["headers"]).status_code == 204
    assert fe.notifications(db, colleague["employee_id"], "eng.post", q["id"]) == 1
    assert fe.scalar(db, "SELECT is_deleted FROM eng.post WHERE id = ?", int(q["id"])) is True


def test_pin_and_hide(db, client, world):
    author, colleague, admin = world["author"], world["colleague"], world["admin"]
    older = fe.post(client, author["headers"], "Welcome to the new intranet")
    fe.post(client, colleague["headers"], "Newer post")

    assert client.patch(f"{API}/posts/{older['id']}/pin", json={"pinned": True},
                        headers=author["headers"]).status_code == 403
    pinned = client.patch(f"{API}/posts/{older['id']}/pin", json={"pinned": True}, headers=admin["headers"])
    assert pinned.status_code == 200 and pinned.json()["data"]["isPinned"] is True
    assert pinned.json()["data"]["canModerate"] is True
    assert _feed_ids(client, colleague["headers"])[0] == older["id"]

    bad = fe.post(client, colleague["headers"], "Something inappropriate")
    hidden = client.patch(f"{API}/posts/{bad['id']}/hide", json={"hidden": True, "reason": "Against the policy"},
                          headers=admin["headers"])
    assert hidden.status_code == 200 and hidden.json()["data"]["isHidden"] is True
    assert hidden.json()["data"]["hiddenReason"] == "Against the policy"
    assert client.get(f"{API}/posts/{bad['id']}", headers=author["headers"]).status_code == 404
    assert bad["id"] not in _feed_ids(client, author["headers"])
    mine = client.get(f"{API}/my-posts", params={"pageSize": 100}, headers=colleague["headers"]).json()["data"]
    assert next(x for x in mine if x["id"] == bad["id"])["isHidden"] is True
    assert fe.notifications(db, colleague["employee_id"], "eng.post", bad["id"]) == 1
    assert fe.events(db, "engagement.post_hidden", bad["id"]) == 1
    # No reactions or comments on a hidden post; it cannot be pinned.
    assert client.post(f"{API}/posts/{bad['id']}/comments", json={"body": "?"},
                       headers=colleague["headers"]).status_code == 409
    assert client.patch(f"{API}/posts/{bad['id']}/pin", json={"pinned": True}, headers=admin["headers"]).status_code == 409

    moderation = client.get(f"{API}/moderation/posts", params={"hiddenOnly": True, "pageSize": 100},
                            headers=admin["headers"]).json()
    assert bad["id"] in [x["id"] for x in moderation["data"]]
    shown = client.patch(f"{API}/posts/{bad['id']}/hide", json={"hidden": False}, headers=admin["headers"])
    assert shown.json()["data"]["isHidden"] is False
    assert bad["id"] in _feed_ids(client, author["headers"])
    client.patch(f"{API}/posts/{older['id']}/pin", json={"pinned": False}, headers=admin["headers"])


def test_permissions(db, client, world):
    staff = world["colleague"]
    # A role with no engagement codes (the Employee role reads the feed).
    nobody = fe.person(db, client, world["company"], world["sales"], role_codes="recruiter", granted=False)
    assert client.get(f"{API}/posts", headers=nobody["headers"]).status_code == 403
    assert client.post(f"{API}/posts", json={"body": "Hi"}, headers=nobody["headers"]).status_code == 403
    assert client.get(f"{API}/moderation/posts", headers=staff["headers"]).status_code == 403
    p = fe.post(client, world["author"]["headers"], "Moderate me")
    assert client.patch(f"{API}/posts/{p['id']}/hide", json={"hidden": True}, headers=staff["headers"]).status_code == 403
    assert client.get(f"{API}/settings", headers=staff["headers"]).status_code == 403
    # A user with no employee record reads the feed but does not post.
    no_employee = client.post(f"{API}/posts", json={"body": "From the admin"}, headers=world["admin"]["headers"])
    assert no_employee.status_code == 403


def test_settings(db, client, world):
    admin, staff = world["admin"], world["colleague"]
    s = client.get(f"{API}/settings", headers=admin["headers"]).json()["data"]
    assert s == {"whoMayPost": "everyone", "allowComments": True, "maxMediaPerPost": 10, "rowVersion": None}
    saved = client.put(f"{API}/settings", json={"whoMayPost": "moderators", "allowComments": False,
                                                "maxMediaPerPost": 1}, headers=admin["headers"])
    assert saved.status_code == 200, saved.text
    rv = saved.json()["data"]["rowVersion"]
    try:
        refused = client.post(f"{API}/posts", json={"body": "Hi"}, headers=staff["headers"])
        assert refused.status_code == 403 and refused.json()["code"] == "POSTING_RESTRICTED"
        # Moderators still post (an HR person with an employee record), within the media limit.
        hr = fe.person(db, client, world["company"], world["sales"], role_codes="hr_manager")
        photos = [fe.photo(client, hr["headers"])["id"] for _ in range(2)]
        assert client.post(f"{API}/posts", json={"body": "x", "mediaFileIds": photos},
                           headers=hr["headers"]).status_code == 422
        hp = fe.post(client, hr["headers"], "Policy update", mediaFileIds=photos[:1])
        off = client.post(f"{API}/posts/{hp['id']}/comments", json={"body": "Thanks"}, headers=staff["headers"])
        assert off.status_code == 403 and off.json()["code"] == "COMMENTS_OFF"
        stale = client.put(f"{API}/settings", json={"whoMayPost": "everyone", "allowComments": True,
                                                    "maxMediaPerPost": 10}, headers=admin["headers"])
        assert stale.status_code == 409
    finally:
        back = client.put(f"{API}/settings", json={"whoMayPost": "everyone", "allowComments": True,
                                                   "maxMediaPerPost": 10, "rowVersion": rv}, headers=admin["headers"])
        assert back.status_code == 200, back.text
