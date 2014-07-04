
var recents = new Hash();
var current_document;

function setActiveStyleSheet(title) {
   var i, a, main;
   for(i=0; (a = document.getElementsByTagName("link")[i]); i++) {
     if(a.getAttribute("rel").indexOf("style") != -1
        && a.getAttribute("title")) {
       a.disabled = true;
       if(a.getAttribute("title") == title) a.disabled = false;
     }
   }
   createCookie("style",title,365)
}

function getActiveStyleSheet() {
 var i, a;
 for(i=0; (a = document.getElementsByTagName("link")[i]); i++) {
  if(a.getAttribute("rel").indexOf("style") != -1
  && a.getAttribute("title")
  && !a.disabled) return a.getAttribute("title");
  }
  return null;
}

function createCookie(name,value,days) {
  if (days) {
    var date = new Date();
    date.setTime(date.getTime()+(days*24*60*60*1000));
    var expires = "; expires="+date.toGMTString();
  }
  else expires = "";
  document.cookie = name+"="+value+expires+"; path=/";
}

function readCookie(name) {
  var nameEQ = name + "=";
  var ca = document.cookie.split(';');
  for(var i=0;i < ca.length;i++) {
    var c = ca[i];
    while (c.charAt(0)==' ') c = c.substring(1,c.length);
    if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
  }
  return null;
}

function getPreferredStyleSheet() {
  var i, a;
  for(i=0; (a = document.getElementsByTagName("link")[i]); i++) {
    if(a.getAttribute("rel").indexOf("style") != -1
       && a.getAttribute("rel").indexOf("alt") == -1
       && a.getAttribute("title")
       ) return a.getAttribute("title");
  }
  return null;
}

window.onload = function(e) {
  var cookie = readCookie("style");
  var title = cookie ? cookie : getPreferredStyleSheet();
  setActiveStyleSheet(title);
}


function refresh_document() {
    display_document(current_document);
}

function display_document(name) {
    
    var f_overlay = $F('overlay');
    var f_view = $F('view');
    var f_sort = $F('sort');
    
    new Ajax.Updater(
    'pod_content','/load',
    { 
        parameters: { paws_key: name, overlay: f_overlay, sort: f_sort, view: f_view },
        onSuccess: function(response) {
            recents.set(name, '1');
            current_document = name;
            var el = update_recents(name);
            el.setStyle({
                backgroundColor: "#ffff99"
            });
            new Effect.Shake(el,{duration: 0.2, distance: 4});
            
            new Ajax.Updater(
                'menu','/menu',
                {parameters: {key: name}}
                );
            new Ajax.Updater(
                'doc_links','/links',
                {parameters: {key: name}}
                );
            new Ajax.Updater(
                'inbound_links','/inbound_links',
                {parameters: {key: name}}
                );
        }
    }
    );
}

function update_recents(name) { // returns the element created for "name" if possible
    var out = null;
    $(recent_searches).childElements().each(function(e) { e.remove() });
    recents.keys().sort().each( function(k) {
        var pm = /^([a-z]+):(.*)$/;
        var match = pm.exec(k);
        var label = match[2];
        var doctype = match[1];
        
        var li = new Element('li');
        var a = new Element("a",{ href: "#", onClick: "display_document('"+k+"')" });
        var x = new Element("a",{ href: "#", 'onClick': "kill_recent('"+k+"')", 'class': "close"});
        
        a.appendChild(document.createTextNode(label));
        x.appendChild(document.createTextNode("×"));

        li.appendChild(x);
        li.appendChild(a);

        $(recent_searches).insert(
            {bottom: li});
        if(name == k) {
            out = li;
        }
    });
    return out;
}

function kill_recent(k) {
    var el = update_recents(k);
    recents.unset(k);
    
    new Effect.DropOut(el,{
        afterFinish: function(){ update_recents() }
    });
}

PAWS_FastSearch = Class.create();
PAWS_FastSearch.prototype = {
    initialize: function(field,request_path) {
        var obj = this;
        obj.s_field = field;
        obj.s_path = request_path;
        obj.keynav = false;
        obj.initializeElements();
    },
    initializeElements: function() {
        var fs_field = $(this.s_field);
        var div_name = "paws_fsearch";
        var obj = this;
        
        this.prev_value = this.terms();
        this.has_results = false;
        this.px = new PeriodicalExecuter(obj.fs_load_praps.bind(obj),0.5);
        this.ajax_active = false;
        this.key_select = false;
        
        var div = $(div_name);
        if (div) {
            fs_field.observe("focus", obj.fs_focus.bind(obj));
            fs_field.observe("blur", obj.fs_blur.bind(obj));
            fs_field.observe("keydown", obj.fs_keynav.bind(obj));
        }
  },
  fs_div: function() {
      var div_name = "paws_fsearch";
      return $(div_name);
  },
  fs_load_praps: function() {
      if(this.prev_value != this.terms()) {
          if(!this.ajax_active) {
              this.fs_load();
          }
      }
  },
  fs_focus: function() {
      if( this.has_results ) {
          this.fs_show()
      }
  },
  fs_blur: function() {
      this.fs_hide();
  },
  fs_hide: function() {
      var obj = this;
      var f = function() {
          obj.fs_div().hide();
      }.delay(0.2);  
  },
  fs_show: function() {
      this.fs_div().show();
  },
  fs_mousefollow: function(lines) {
      var obj = this;
      lines.each( function(e) {
          e.observe('mouseover',function(event) {
              obj.fs_result_over(event, e);
          });
          e.observe('click',function(event) {
              obj.fs_result_click(event, e);
          });
      });
  },
  fs_result_over: function(ev,elt) {
      if(this.selected_elt != null) {
          this.selected_elt.removeClassName("hilight");
      }
      this.selected_elt = elt;
      this.keynav = false;
      elt.addClassName("hilight");
  },
  fs_keynav: function(ev) {
      if(ev.keyCode == Event.KEY_UP || ev.keyCode == Event.KEY_DOWN) {
          var next_el = this.fs_div().select(".result_line").first();
          if(this.selected_elt != null) {
              switch (ev.keyCode) {
              case Event.KEY_UP:
                  next_el = this.selected_elt.previous(".result_line");
                  break;
              case Event.KEY_DOWN:
                  next_el = this.selected_elt.next(".result_line");
                  break;
              }
          }
          if(next_el) {
              if(this.selected_elt)
                  this.selected_elt.removeClassName("hilight");
              this.selected_elt = next_el;
              this.selected_elt.addClassName("hilight");
              this.keynav = true;
          }
          ev.stop();
      } else if(this.keynav && 
                this.selected_elt &&
                (ev.keyCode == Event.KEY_LEFT || ev.keyCode == Event.KEY_RIGHT)) {
          var sibs = this.selected_elt.previousSiblings();
          var position = sibs.length - 1; /* one for heading */
          var column = this.selected_elt.up(".fs_section");
          var next_el = null;
          switch (ev.keyCode) {
              case Event.KEY_LEFT:
                next_col = column.previous(".fs_section");
                break;
              case Event.KEY_RIGHT:
                next_col = column.next(".fs_section");
                break;
          }
          if(next_col) {
              var col_results = next_col.select(".result_line");
              if(col_results.length < position) {
                  next_el = col_results.last();
              } else {
                  next_el = col_results[position];
              }
              if(next_el) {
                  if(this.selected_elt)
                      this.selected_elt.removeClassName("hilight");
                  this.selected_elt = next_el;
                  this.selected_elt.addClassName("hilight");
              }
          }
          ev.stop()
      } else if(ev.keyCode != Event.KEY_RETURN) {
          this.keynav = false;
      }

      if(ev.keyCode == Event.KEY_RETURN) {
          if(this.keynav && this.selected_elt) {
              var paws_link = this.selected_elt.readAttribute('paws_link')
              display_document(paws_link);
              ev.stop();
          }
      }
      
  },
  fs_result_click: function(ev,elt) {
      var paws_link = elt.readAttribute('paws_link')
      display_document(paws_link);
  },
  fs_load: function() {
      var div = this.fs_div();
      var path = this.s_path;
      var obj = this;
      var tval = this.terms();
      this.ajax_active = true;
      new Ajax.Updater(div,path, {
          parameters: { "terms" : tval },
          evalScripts: false,
          method: "GET",
          onComplete: function(transport) {
              var response_divs = div.select("div.fs_section");
              var section_count = response_divs.length;
              div.setStyle({width: '' + (300 * section_count) + 'px', position: 'absolute'})
              obj.ajax_active = false;
              obj.selected_elt = null;
              
              var total_lines = div.select("div.result_line");
              if(total_lines.length == 0) {
                  obj.fs_hide();
                  return true;
              } else {
                  obj.has_results = true;
                  obj.fs_div().show();
                  obj.fs_mousefollow(total_lines);
                  obj.prev_value = tval;
              }
          }
      }
      );
  },
  terms: function() {
      return $(this.s_field).getValue();
  }
}