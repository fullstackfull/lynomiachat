<script setup>
import SearchResultSection from './SearchResultSection.vue';
import SearchResultArticleItem from './SearchResultArticleItem.vue';

defineProps({
  articles: {
    type: Array,
    default: () => [],
  },
  query: {
    type: String,
    default: '',
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  showTitle: {
    type: Boolean,
    default: true,
  },
});
</script>

<template>
  <SearchResultSection
    :title="$t('SEARCH.SECTION.ARTICLES')"
    :empty="!articles.length"
    :query="query"
    :show-title="showTitle"
    :is-fetching="isFetching"
  >
    <ul v-if="articles.length" class="space-y-3 list-none">
      <li v-for="article in articles" :key="article.id">
        <SearchResultArticleItem
          :title="article.title"
          :description="article.description"
          :content="article.content"
          :slug="article.slug"
          :portal-slug="article.portalSlug"
          :locale="article.locale"
          :category="article.categoryName"
          :status="article.status"
          :updated-at="article.updatedAt"
        />
      </li>
    </ul>
  </SearchResultSection>
</template>
