import { statsDocId, growthFraction } from '../dailyStats';

/// Pure logic behind the daily-stats snapshot / growth computation (H20).
describe('statsDocId', () => {
  it('is the UTC yyyy-mm-dd of the date', () => {
    expect(statsDocId(new Date('2026-07-22T03:00:00Z'))).toBe('2026-07-22');
  });

  it('rolls to the UTC day, not local', () => {
    expect(statsDocId(new Date('2026-07-22T23:30:00Z'))).toBe('2026-07-22');
  });
});

describe('growthFraction', () => {
  it('is the fractional change from baseline to current', () => {
    expect(growthFraction(110, 100)).toBeCloseTo(0.10, 9);
  });

  it('is negative when followers dropped', () => {
    expect(growthFraction(80, 100)).toBeCloseTo(-0.20, 9);
  });

  it('is null when there is no baseline (no history yet)', () => {
    expect(growthFraction(100, null)).toBeNull();
  });

  it('is null when the baseline is zero (avoid divide-by-zero / infinite %)', () => {
    expect(growthFraction(50, 0)).toBeNull();
  });
});
