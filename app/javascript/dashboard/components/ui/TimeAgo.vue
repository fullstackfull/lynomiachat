<script>
const MINUTE_IN_MILLI_SECONDS = 60000;
const HOUR_IN_MILLI_SECONDS = MINUTE_IN_MILLI_SECONDS * 60;
const DAY_IN_MILLI_SECONDS = HOUR_IN_MILLI_SECONDS * 24;

import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

export default {
  name: 'TimeAgo',
  props: {
    isAutoRefreshEnabled: {
      type: Boolean,
      default: true,
    },
    lastActivityTimestamp: {
      type: [String, Date, Number],
      default: '',
    },
    createdAtTimestamp: {
      type: [String, Date, Number],
      default: '',
    },
    conversationId: {
      type: [String, Number],
      default: '',
    },
  },
  setup() {
    return { exactTimestamp: useExactTimestamp() };
  },
  data() {
    return {
      lastActivityAtTimeAgo: dynamicTime(this.lastActivityTimestamp),
      createdAtTimeAgo: dynamicTime(this.createdAtTimestamp),
      timer: null,
    };
  },
  computed: {
    lastActivityTime() {
      return shortTimestamp(this.lastActivityAtTimeAgo);
    },
    createdAtTime() {
      return shortTimestamp(this.createdAtTimeAgo);
    },
    createdAt() {
      return `${this.$t(
        'CHAT_LIST.CHAT_TIME_STAMP.CREATED.OLDEST'
      )} ${this.exactTimestamp(this.createdAtTimestamp)}`;
    },
    lastActivity() {
      return `${this.$t(
        'CHAT_LIST.CHAT_TIME_STAMP.LAST_ACTIVITY.NOT_ACTIVE'
      )} ${this.exactTimestamp(this.lastActivityTimestamp)}`;
    },
    tooltipText() {
      return `${this.createdAt}\n${this.lastActivity}`;
    },
    // Age and freshness are two different facts and both are shown -- but a conversation that has had no
    // reply since it arrived renders them as the same number twice ("9h • 9h"), which reads as noise and
    // leaves the reader unable to tell which half is which. The tooltip still carries both exact times.
    displayTime() {
      return this.createdAtTime === this.lastActivityTime
        ? this.lastActivityTime
        : `${this.createdAtTime} • ${this.lastActivityTime}`;
    },
  },
  watch: {
    lastActivityTimestamp() {
      this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
    },
    createdAtTimestamp() {
      this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
    },
    conversationId() {
      // Reset display values and timer when the row is recycled to a different conversation.
      this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
      this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
      if (this.isAutoRefreshEnabled) {
        clearTimeout(this.timer);
        this.createTimer();
      }
    },
  },
  mounted() {
    if (this.isAutoRefreshEnabled) {
      this.createTimer();
    }
  },
  unmounted() {
    clearTimeout(this.timer);
  },
  methods: {
    createTimer() {
      this.timer = setTimeout(() => {
        this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
        this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
        this.createTimer();
      }, this.refreshTime());
    },
    refreshTime() {
      const timeDiff = Date.now() - this.lastActivityTimestamp * 1000;
      if (timeDiff > DAY_IN_MILLI_SECONDS) {
        return DAY_IN_MILLI_SECONDS;
      }
      if (timeDiff > HOUR_IN_MILLI_SECONDS) {
        return HOUR_IN_MILLI_SECONDS;
      }

      return MINUTE_IN_MILLI_SECONDS;
    },
  },
};
</script>

<template>
  <div
    v-tooltip.top="{
      content: tooltipText,
      popperClass: 'whitespace-pre-line',
      delay: { show: 1000, hide: 0 },
    }"
    class="ms-auto leading-4 text-xs tabular-nums text-n-slate-10 hover:text-n-slate-11"
  >
    <span>{{ displayTime }}</span>
  </div>
</template>
