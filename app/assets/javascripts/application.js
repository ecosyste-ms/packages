//= require chartkick
//= require Chart.bundle
//= require popper
//= require bootstrap 
//= require jquery

function renderFileList(files, path) {
  $('#files-content').hide().html('');
  var items = [];
  
  if (path && path.length > 0){
    var parts = path.split('/')
    var parent = parts.slice(0, parts.length - 1).join('/');
    var parser = new URL(window.location)
    parser.searchParams.set('path', parent)
    items.push( "<li class='list-group-item'><a href=" + parser.href + ">..</a></li>" );
  }

  $.each(files, function( i,val ) {
    if (val.split('/').length == 1) {
      var parser = new URL(window.location)
      if (path && path.length > 0){
        parser.searchParams.set('path', path + '/' + val)
      } else {
        parser.searchParams.set('path', val)
      }
      items.push( "<li class='list-group-item'><a href=" + parser.href + ">" + val + "</a></li>" );
    }
  });
  
  $(items.join( "" )).appendTo( "#files-list" );
}

function renderFile(file){
  console.log(file)
  $('#files-content').html('').show();
  $("<pre><code id='files-body'></code></pre>").appendTo( "#files-content" );
  $('#files-body').text(file.contents)
  hljs.highlightAll()
}

function renderFileHeader(basename, path){
  var parser = new URL(window.location)
  parser.searchParams.set('path', '')
  $('#files-header').append($('<a href="'+parser.href+'">' + basename + '</a>')) // todo make path sections clickable
  if (path && path.length > 0){
    var parts = path.split('/')
    $.each(parts, function( i,val ) {
      $('#files-header').append(' / ')
      if (i < parts.length - 1){
        var parser = new URL(window.location)
        var parent = parts.slice(0, i + 1 - parts.length).join('/');
        parser.searchParams.set('path', parent)
        $('#files-header').append($('<a href="'+parser.href+'">' + val + '</a>'))
      } else {
        $('#files-header').append(val)
      }
    })
  }
}

function renderReadme(data){
  console.log(data)
  $('#readme-header').text(data['name'])
  $('#readme-content').html('').show();
  $("<div id='readme-body'></div>").appendTo( "#readme-content" );
  $('#readme-body').html(data.html)
}

$( document ).ready(function() {

  if ($('#files').length > 0) {
    var download_url = $('#files').data('url');
    var basename = $('#files').data('basename');
    var path = $('#files').data('path');
    
    var list_url = "https://archives.ecosyste.ms/api/v1/archives/list?url=" + download_url
    var contents_url = "https://archives.ecosyste.ms/api/v1/archives/contents?url=" + download_url + "&path=" + path

    if(path.length > 0){
      var url = contents_url
    } else{
      var url = list_url
    }

    renderFileHeader(basename, path)

    $.getJSON(url, function( data ) {
      if(path.length > 0){
        if(data.directory){
          renderFileList(data.contents, path)  
        } else{
          renderFile(data, path)
        }
      } else{
        renderFileList(data, path)
      }
    }).fail(function() { $('#files-content').html('Error loading file').show(); });
  }

  if ($('#readme').length > 0) {
    var download_url = $('#files').data('url');
    var readme_url = "https://archives.ecosyste.ms/api/v1/archives/readme?url=" + download_url

    $.getJSON(readme_url, function( data ) {
        renderReadme(data)
    }).fail(function() { $('#readme-content').html('Error loading readme').show(); });

  }
  
});