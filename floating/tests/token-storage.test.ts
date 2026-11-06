import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { saveRefreshToken } from "../src/auth.ts";

test("Linux token writes stay private without changing an existing mount's permissions", { skip: process.platform !== "linux" }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "floating-token-test-"));
  const previous = process.env.COGNITO_REFRESH_TOKEN_FILE;
  try {
    await chmod(directory, 0o750);
    process.env.COGNITO_REFRESH_TOKEN_FILE = join(directory, "refresh-token");
    await saveRefreshToken("unit-test-refresh-value");
    assert.equal(await readFile(process.env.COGNITO_REFRESH_TOKEN_FILE, "utf8"), "unit-test-refresh-value\n");
    assert.equal((await stat(process.env.COGNITO_REFRESH_TOKEN_FILE)).mode & 0o777, 0o600);
    assert.equal((await stat(directory)).mode & 0o777, 0o750);
    assert.deepEqual(await readdir(directory), ["refresh-token"]);
  } finally {
    if (previous === undefined) delete process.env.COGNITO_REFRESH_TOKEN_FILE;
    else process.env.COGNITO_REFRESH_TOKEN_FILE = previous;
    await rm(directory, { recursive: true, force: true });
  }
});

test("failed token replacement removes the temporary credential file", { skip: process.platform !== "linux" }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "floating-token-test-"));
  const previous = process.env.COGNITO_REFRESH_TOKEN_FILE;
  try {
    const occupied = join(directory, "occupied");
    await mkdir(occupied);
    process.env.COGNITO_REFRESH_TOKEN_FILE = occupied;
    await assert.rejects(saveRefreshToken("unit-test-refresh-value"));
    assert.deepEqual(await readdir(directory), ["occupied"]);
  } finally {
    if (previous === undefined) delete process.env.COGNITO_REFRESH_TOKEN_FILE;
    else process.env.COGNITO_REFRESH_TOKEN_FILE = previous;
    await rm(directory, { recursive: true, force: true });
  }
});
