function sortedKeys(obj) {
  var keys = []

  for (key in obj) {
    keys.push(key)
  }
  keys.sort()
  return keys
}

function cluster() {
  var date = document.getElementById("c_date").value
  $('#loading').empty()
  $('#clusters').empty()

  $('#loading').append("Loading 10 clusters for "+ date +"...")
  $.getJSON("/date/"+date+"/n/10", cluster_callback)
}

function get_elt_or(array, ind) {
  if (array[ind]) {
    return (array[ind]).join(", ")
  } else {
    return ""
  }
}

function cluster_callback(json) {
  $('#loading').empty()
  $('#loading').append("Finished loading clusters.")
  var html = '<table>'
           + ' <thead>'
           + '  <th class="clusters"> Cluster </th>'
           + '  <th class="media"> Media </th>'
           + '  <th class="internal"> Int. Feature </th>'
           + '  <th class="external"> Ext. Feature </th>'
           + ' </thead>'
           + ' <tbody>'

  for (key in sortedKeys(json)) {
    var cluster_items = json[key][1]
    var int_features = json[key][0][0]
    var ext_features = json[key][0][1]
    var cluster_html = '<tr>'
                      +'  <th class="clusters">'+ key +'</th>'
                      +'</tr>'

    var count = 0
    for (key2 in cluster_items) {
      var int_feature = get_elt_or(int_features, count)
      var ext_feature = get_elt_or(ext_features, count)
      count++

      cluster_html += '<tr> <th></th>'
                     +' <td class="media">'+ cluster_items[key2] +'</td>'
                     +' <td class="internal">'+ int_feature +'</td>'
                     +' <td class="external">'+ ext_feature +'</td>'
                     +'</tr>'
    }

    html += cluster_html
  }

  $('#clusters').append(html)
}