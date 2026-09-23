/**
 * TypeScript port of ../../bin/goal-block-check (see ../../spec/goal-block.md).
 * Must stay a line-for-line port: parity is enforced by test/validator.test.ts,
 * which runs both this function and the shell script over the same fixtures.
 */

const MAX_CHARS = 4000;
const HEADER = /^Execute plan "(.+)" \((.+)\)\. Goal rows:$/;
const LEAD_NUM = /^(\d+)\s*(.*)$/;
const ROW_BODY = /^(\S.*?)\s*:(.*)$/;

/** Text between '## Goal block' and the next '## ' heading, else the whole input. */
function extract(lines: string[]): string[] {
  for (let index = 0; index < lines.length; index++) {
    if (lines[index].trim() === "## Goal block") {
      let end = lines.length;
      for (let stop = index + 1; stop < lines.length; stop++) {
        if (lines[stop].startsWith("## ")) {
          end = stop;
          break;
        }
      }
      return lines.slice(index + 1, end);
    }
  }
  return lines;
}

/**
 * Validate a goal block. Returns an empty array when valid, otherwise one
 * problem string per line (same wording as goal-block-check's stderr lines).
 */
export function validateGoalBlock(raw: string): string[] {
  let lines = extract(raw.split("\n"));
  while (lines.length && lines[0].trim() === "") lines.shift();
  while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();

  const problems: string[] = [];
  if (lines.length === 0) {
    problems.push("missing header line");
    return problems;
  }

  const joined = lines.join("\n");
  const size = Array.from(joined).length; // Unicode characters, not UTF-16 units or bytes
  if (size > MAX_CHARS) {
    problems.push(`too long: ${size}/${MAX_CHARS} characters`);
  }
  if (!HEADER.test(lines[0])) {
    problems.push(
      'missing header line: expected Execute plan "<plan name>" (<plan file path or reference>). Goal rows:',
    );
  }

  let expected = 1;
  let validRows = 0;
  let trailer = false;
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === "") continue;
    const lead = LEAD_NUM.exec(line);
    if (!lead) {
      if (validRows === 0) problems.push("free text before row 1");
      trailer = true;
      continue;
    }
    const number = Number.parseInt(lead[1], 10);
    if (number !== expected) {
      problems.push(`rows not consecutive: expected ${expected} got ${number}`);
    }
    expected = number + 1;
    if (trailer) {
      problems.push(`row ${number}: row after trailing free text`);
    }
    const body = ROW_BODY.exec(lead[2]);
    if (!body) {
      problems.push(`row ${number}: expected "<n> <label>: <check>"`);
    } else if (!body[2].trim()) {
      problems.push(`row ${number}: missing check after ':'`);
    } else {
      validRows++;
    }
  }
  if (validRows === 0) problems.push("no goal rows");

  return problems;
}

export const GOAL_BLOCK_MAX_CHARS = MAX_CHARS;
