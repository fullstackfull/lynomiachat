import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  BULK_COMPLETION_TIMEOUT,
  waitForBulkActionCompletion,
} from '../bulkActionCompletion';

describe('waitForBulkActionCompletion', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    emitter.all.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
    emitter.all.clear();
  });

  it('resolves when the job announces it has finished', async () => {
    const settled = vi.fn();
    const waiting = waitForBulkActionCompletion().then(settled);

    await vi.advanceTimersByTimeAsync(0);
    expect(settled).not.toHaveBeenCalled();

    emitter.emit(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED, { account_id: 1 });
    await waiting;

    expect(settled).toHaveBeenCalled();
  });

  it('resolves on its own if the announcement never arrives', async () => {
    const settled = vi.fn();
    const waiting = waitForBulkActionCompletion().then(settled);

    await vi.advanceTimersByTimeAsync(BULK_COMPLETION_TIMEOUT - 1);
    expect(settled).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    await waiting;

    expect(settled).toHaveBeenCalled();
  });

  // Both paths have to unsubscribe: the page calls this once per bulk action, and a listener left behind would
  // resolve the next wait the moment any later announcement arrived.
  it('stops listening once it has resolved, whichever way it resolved', async () => {
    await (() => {
      const waiting = waitForBulkActionCompletion();
      emitter.emit(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED, {});
      return waiting;
    })();
    expect(emitter.all.get(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED)).toEqual(
      []
    );

    const timedOut = waitForBulkActionCompletion();
    await vi.advanceTimersByTimeAsync(BULK_COMPLETION_TIMEOUT);
    await timedOut;
    expect(emitter.all.get(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED)).toEqual(
      []
    );
  });

  it('does not keep a timer alive after the announcement', async () => {
    const waiting = waitForBulkActionCompletion();
    emitter.emit(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED, {});
    await waiting;

    expect(vi.getTimerCount()).toBe(0);
  });
});
