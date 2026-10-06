import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// A contact bulk action is queued, not applied, by the time the request returns: the endpoint answers as soon
// as `Contacts::BulkActionJob` is enqueued. Refetching straight away reads the list before the job has written
// to it, so the rows come back exactly as they were. The job broadcasts once it is done — this is how a caller
// waits for that.
//
// The timeout is the only thing standing between a dropped websocket and a bar that spins forever, so it
// resolves rather than rejecting: the refetch that follows is correct either way, just later than it could be.
export const BULK_COMPLETION_TIMEOUT = 15000;

export const waitForBulkActionCompletion = (
  timeout = BULK_COMPLETION_TIMEOUT
) =>
  new Promise(resolve => {
    let timer = null;
    const settle = () => {
      clearTimeout(timer);
      emitter.off(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED, settle);
      resolve();
    };
    emitter.on(BUS_EVENTS.CONTACT_BULK_ACTION_COMPLETED, settle);
    timer = setTimeout(settle, timeout);
  });
