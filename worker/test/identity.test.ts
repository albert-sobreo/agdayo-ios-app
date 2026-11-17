import { describe, expect, it } from "vitest";
import { pickGoogleAccount } from "../src/identity";

describe("pickGoogleAccount", () => {
  it("only matches an account that signs in with that Google address", () => {
    const users = [
      { localId: "email-only", providerUserInfo: [{ providerId: "password", email: "a@gmail.com" }] },
      { localId: "google", providerUserInfo: [{ providerId: "google.com", email: "A@gmail.com" }] },
    ];
    expect(pickGoogleAccount(users, "a@gmail.com")).toBe("google");
    expect(pickGoogleAccount([users[0]!], "a@gmail.com")).toBeUndefined();
    expect(pickGoogleAccount([{ ...users[1]!, disabled: true }], "a@gmail.com")).toBeUndefined();
    expect(pickGoogleAccount(undefined, "a@gmail.com")).toBeUndefined();
  });
});
