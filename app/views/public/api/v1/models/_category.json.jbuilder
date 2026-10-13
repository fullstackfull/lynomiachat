json.name category.name
json.slug category.slug
json.locale category.locale
json.description category.description
json.position category.position

json.meta do
  json.articles_count category.portal_articles.published.size
end
