import { describe, expect, it } from "vitest";
import { decodeFields, encodeFields, Firestore, FsDouble, FsTimestamp } from "../src/firestore";

const account = { project_id: "agdayo-app", client_email: "sa@agdayo-app.iam.gserviceaccount.com", private_key: "unused" };

describe("Firestore values", () => {
  it("encodes the shapes the app's DTOs decode", () => {
    expect(
      encodeFields({
        title: "Gardens",
        rooms: 2,
        cost: new FsDouble(20),
        rate: 1.5,
        date: new FsTimestamp("2026-12-10T01:00:00.000Z"),
        tags: ["a"],
        splits: {},
        skipped: undefined,
        note: null,
      }),
    ).toEqual({
      title: { stringValue: "Gardens" },
      rooms: { integerValue: "2" },
      cost: { doubleValue: 20 },
      rate: { doubleValue: 1.5 },
      date: { timestampValue: "2026-12-10T01:00:00.000Z" },
      tags: { arrayValue: { values: [{ stringValue: "a" }] } },
      splits: { mapValue: { fields: {} } },
      note: { nullValue: null },
    });
  });

  it("decodes timestamps to ISO strings and numbers to numbers", () => {
    expect(
      decodeFields({
        date: { timestampValue: "2026-12-10T01:00:00Z" },
        rooms: { integerValue: "2" },
        ids: { arrayValue: {} },
        nested: { mapValue: { fields: { ok: { booleanValue: true } } } },
      }),
    ).toEqual({ date: "2026-12-10T01:00:00.000Z", rooms: 2, ids: [], nested: { ok: true } });
  });
});

describe("Firestore writes", () => {
  const db = new Firestore(account);
  const root = "projects/agdayo-app/databases/(default)/documents";

  it("creates with a precondition and server timestamps", () => {
    expect(db.encodeWrite({ kind: "set", path: "trips/T", fields: { name: "SG" }, serverTimestamps: ["createdAt"], mustNotExist: true })).toEqual({
      update: { name: `${root}/trips/T`, fields: { name: { stringValue: "SG" } } },
      updateTransforms: [{ fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: { exists: false },
    });
  });

  it("updates only the given fields of an existing document", () => {
    expect(db.encodeWrite({ kind: "update", path: "trips/T/activities/A", fields: { title: "New", cost: undefined } })).toEqual({
      update: { name: `${root}/trips/T/activities/A`, fields: { title: { stringValue: "New" } } },
      updateMask: { fieldPaths: ["title"] },
      currentDocument: { exists: true },
    });
  });

  it("adds to an array without touching other fields, like arrayUnion with merge", () => {
    expect(db.encodeWrite({ kind: "arrayUnion", path: "users/U", field: "memberOfTripIDs", values: ["T"] })).toEqual({
      update: { name: `${root}/users/U`, fields: {} },
      updateMask: { fieldPaths: [] },
      updateTransforms: [{ fieldPath: "memberOfTripIDs", appendMissingElements: { values: [{ stringValue: "T" }] } }],
    });
  });
});
