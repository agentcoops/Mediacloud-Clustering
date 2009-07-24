function cluster() {
  var date = document.getElementById("c_date").value;
  var n = document.getElementById("n").value;
  $('#loading').empty()
  $('#clusters').empty()

  $('#loading').append("Loading "+ n +" clusters for "+ date +"...")
  $.getJSON("/date/"+date+"/n/"+n, cluster_callback)
}

function cluster_callback(json) {
  $('#loading').empty()
  $('#loading').append("Finished loading "+n+" clusters for "+date)
  var html = '<table>'
           + ' <thead>'
           + '  <th class="clusters"> Cluster </th>'
           + '  <th class="media"> Media </th>'
           + ' </thead>'
           + ' <tbody>'

  for (key in json) {
    var cluster_html = '<tr>'
                      +'  <th class="clusters">'+ key +'</th>'
                      +'</tr>'
    for (media in json[key]) {
      cluster_html += '<tr><th></th>'
                     +' <td class="media">'+ media +'</td></tr>'
    }

    html += cluster_html
  }

  $('#clusters').append(html)
}