
var recents = { };
var current_document;
var current_section;

var KEY_LEFT = 37;
var KEY_UP = 38;
var KEY_RIGHT = 39;
var KEY_DOWN = 40;
var KEY_RETURN = 13;

(function(){
  var initializing = false, fnTest = /xyz/.test(function(){xyz;}) ? /\b_super\b/ : /.*/;
 
  // The base Class implementation (does nothing)
  this.Class = function(){};
 
  // Create a new Class that inherits from this class
  Class.extend = function(prop) {
    var _super = this.prototype;
   
    // Instantiate a base class (but only create the instance,
    // don't run the init constructor)
    initializing = true;
    var prototype = new this();
    initializing = false;
   
    // Copy the properties over onto the new prototype
    for (var name in prop) {
      // Check if we're overwriting an existing function
      prototype[name] = typeof prop[name] == "function" &&
        typeof _super[name] == "function" && fnTest.test(prop[name]) ?
        (function(name, fn){
          return function() {
            var tmp = this._super;
           
            // Add a new ._super() method that is the same method
            // but on the super-class
            this._super = _super[name];
           
            // The method only need to be bound temporarily, so we
            // remove it when we're done executing
            var ret = fn.apply(this, arguments);        
            this._super = tmp;
           
            return ret;
          };
        })(name, prop[name]) :
        prop[name];
    }
   
    // The dummy class constructor
    function Class() {
      // All construction is actually done in the init method
      if ( !initializing && this.init )
        this.init.apply(this, arguments);
    }
   
    // Populate our constructed prototype object
    Class.prototype = prototype;
   
    // Enforce the constructor to be what we expect
    Class.prototype.constructor = Class;
 
    // And make this class extendable
    Class.extend = arguments.callee;
   
    return Class;
  };
})();

(function($){
    $.getQuery = function( query ) {
        query = query.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]");
        var expr = "[\\?&]"+query+"=([^&#]*)";
        var regex = new RegExp( expr );
        var results = regex.exec( window.location.href );
        if( results !== null ) {
            return decodeURIComponent(results[1].replace(/\+/g, " "));
        } else {
            return false;
        }
    };
})(jQuery);

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

function refresh_document() {
    display_document(current_document);
}

function display_document(name,section) {
    var f_overlay = $('#overlay:checked').val();
    var f_view = $('#view').val();
    var f_sort = $('#sort:checked').val();
    section = section || '';
    
    new $.ajax({
        url: '/_load',
        type: "get",
        dataType: "json",
        data: { paws_key: name, section: section, overlay: f_overlay, sort: f_sort, view: f_view },
        success: function(response){
            $('#pod_content').html(response.content);
            $('#menu').html(response.menu);
            $('#doc_links').html(response.links);
            $('#inbound_links').html(response.inbound_links);
            recents[name] = 1;
            current_document = name;
            current_section = '';
            var el = update_recents(name);
            el.addClass('uk-active');
            el.hide().fadeIn(500);

            /* Trigger highlight.js */
            $("pre code").each(function() {
                hljs.highlightBlock(this);
            });
            attach_listeners();
        }
    });
}

function paws_go(section_name, section_id) {
    current_section = section_name;
    UIkit.Utils.scrollToElement(UIkit.$('#sa_' + section_id));
    set_url_state();
    return false;
}

function attach_listeners() {
    $('button.annotate_button').each(function(elt) {
        $(this).on("click",edit_annotation);
    });
}

function overlay_on() {
    var overlay = $('#edit_overlay');
    overlay.addClass('on');
    $(overlay).on("click",overlay_off);
}

function overlay_off(ev) {
    if(ev) ev.stopPropagation();
    $('.popover').removeClass('on');
    
    return false;
}

function edit_annotation(event) {
    event.stopPropagation();
    var elt = this;
    var form = $(elt).parent("form");
    var params = form.serialize();

    overlay_on();
    var ed = $('#annotate_edit');
    ed.innerHTML = '<div class="loader" />'
    ed.addClass("on");
    
    new $.ajax({
        url: "/_edit_annotation",
        type: "post",
        dataType: "html",
        data: params,
        success: function(response) {
            $(ed).html(response);
            $('#edit-save').on("click",save_annotation);
        }
    });

    return false;
}

function save_annotation(ev) {
    var elt = this;
    ev.stopPropagation();
    var form = $(elt).parent("form");
    var params = form.serialize();
    var module_name = form.children('[name="module"]').val()
    
    overlay_on();
    var ed = $('annotate_edit');
    ed.innerHTML = '<div class="loader" />'
    
    new $.ajax({
        url: "/_save_annotation",
        type: "post",
        dataType: "json",
        data: params,
        success: function(response) {
            if(response.saved == 'yes') {
                overlay_off();
                var f = function() { display_document(module_name) };
                _.delay(f,1000);
            }
        }
    });
    
    return false;
}

function load_recents() {
    var d = $.getQuery('d');
    
    if(!d)
        return;
    var all = d.split(",");
    _.each(all,function(x) { recents[x] = 1; });
//    display_document(c);
}

function set_url_state() {
    var count_recents = _.keys(recents).length;
    var slug = "/" + current_document;
    var f_view = $('#view').val();
    
    if(f_view != 'normal') {
        slug += '/' + f_view;
    }
    
    if(current_section) {
        slug += "/@" + current_section;
    }
    
    if(count_recents > 1) {
        slug += "?d=" + _.without(_.keys(recents), current_document).sort().join(",");
    }
    
    history.pushState( {
      old_text: "PAWS",
      new_text: "PAWS",
      slug: slug
    }, null, slug);
}

function update_recents(name) { // returns the element created for "name" if possible
    var out = null;
    $('#recent_searches').children().each(function() { this.remove() });
    
    _.each(_.keys(recents).sort(), function(k) {
        var label = k;
    
        var li = $("<li></li>");
        var a = $("<a href='#'>"+label+"</a>"); a.attr("onClick","display_document('"+k+"')" );
        var x = $("<a href='#' style='float:right; clear: right;' class='uk-close'></a>"); x.attr( 'onClick', "kill_recent('"+k+"')");
    
        li.append(x);
        li.append(a);

        $('#recent_searches').append(li);
        if(name == k) {
            out = li;
        }
    });
    
    set_url_state();
    
    return out;
}

function kill_recent(k) {
    var el = update_recents(k);
    el.fadeOut(500,function() {
        delete recents[k];
        update_recents();
    });
}

var PAWS_FastSearch = Class.extend({
      init: function(field,request_path) {
          var obj = this;
          obj.s_field = field;
          obj.s_path = request_path;
          obj.keynav = false;
          obj.initializeElements();
      },
      px: function() {
          var obj = this;
          this.fs_load_praps();
          setTimeout(function() { obj.px() }, 500 )
      },
      initializeElements: function() {
          var fs_field = $('#'+this.s_field);
          var div_name = "paws_fsearch";
          var obj = this;

          this.prev_value = this.terms();
          this.has_results = false;
          this.px(); // Start periodic execute on this.px every half second
          this.ajax_active = false;
          this.key_select = false;

          var div = $(div_name);
          if (div) {
              $(fs_field).on("focus", function(event) { obj.fs_focus() } );
              $(fs_field).on("blur", function(event) { obj.fs_blur() } );
              $(fs_field).keydown( function(event) { obj.fs_keynav(event) } );
          }
    },
    fs_div: function() {
        var div_name = "paws_fsearch";
        return $('#'+div_name);
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
        setTimeout( function() {
            obj.fs_div().css('display','none');
        },200 );  
    },
    fs_show: function() {
        this.fs_div().show();
    },
    fs_mousefollow: function(lines) {
        var obj = this;
        lines.each( function() {
            $(this).on('mouseover',function(event) {
                obj.fs_result_over(event, this);
            });
            $(this).on('click',function(event) {
                obj.fs_result_click(event, this);
            });
        });
    },
    fs_result_over: function(ev,elt) {
        if(this.selected_elt != null) {
            $(this.selected_elt).removeClass("hilight");
        }
        this.selected_elt = elt;
        this.keynav = false;
        $(elt).addClass("hilight");
    },
    fs_keynav: function(ev) {
        if(ev.which == KEY_UP || ev.which == KEY_DOWN) {
            var next_el = this.fs_div().find(".result_line").first();
            if(this.selected_elt != null) {
                switch (ev.which) {
                case KEY_UP:
                    next_el = $(this.selected_elt).prev(".result_line");
                    break;
                case KEY_DOWN:
                    next_el = $(this.selected_elt).next(".result_line");
                    break;
                }
            }
            if(next_el.length > 0) {
                if(this.selected_elt)
                    $(this.selected_elt).removeClass("hilight");
                this.selected_elt = next_el;
                $(this.selected_elt).addClass("hilight");
                this.keynav = true;
            }
            ev.stopPropagation();
        } else if(this.keynav && 
                  this.selected_elt &&
                  (ev.which == KEY_LEFT || ev.which == KEY_RIGHT)) {
            var sibs = $(this.selected_elt).prevAll();
            var position = sibs.length - 1; /* one for heading */
            var column = $(this.selected_elt).parent(".fs_section");
            var next_el = null;
            switch (ev.which) {
                case KEY_LEFT:
                  next_col = $(column).prev(".fs_section");
                  break;
                case KEY_RIGHT:
                  next_col = $(column).next(".fs_section");
                  break;
            }
            if(next_col.length > 0) {
                var col_results = next_col.children(".result_line");
                if(col_results.length <= position) {
                    next_el = col_results.last();
                } else {
                    next_el = col_results[position];
                }
                if(next_el) {
                    if(this.selected_elt)
                        $(this.selected_elt).removeClass("hilight");
                    this.selected_elt = next_el;
                    $(this.selected_elt).addClass("hilight");
                }
            }
            ev.stopPropagation()
        } else if(ev.which != KEY_RETURN) {
            this.keynav = false;
        }

        if(ev.which == KEY_RETURN) {
            if(this.keynav && this.selected_elt) {
                var paws_link = $(this.selected_elt).attr('paws_link')
                display_document(paws_link);
                ev.stopPropagation();
            }
        }

    },
    fs_result_click: function(ev,elt) {
        var paws_link = $(elt).attr('paws_link')
        display_document(paws_link);
    },
    fs_load: function() {
        var div = this.fs_div();
        var path = this.s_path;
        var obj = this;
        var tval = this.terms();
        this.ajax_active = true;
        $.ajax({
            url: path, type: "get", dataType: "html",
            data: { terms: tval },
            success: function(response){
                var response_divs = $(div).html(response).find(".fs_section");
                
                var section_count = response_divs.length;
                div.attr("class","uk-grid uk-grid-small");
                div.addClass("uk-width-medium-"+section_count+"-4");
                div.addClass("uk-width-small-1-1");
                div.css('position', 'absolute')
                obj.ajax_active = false;
                obj.selected_elt = null;

                var total_lines = div.find(".result_line");
                if(total_lines.length == 0) {
                    obj.fs_hide();
                    return true;
                } else {
                    obj.has_results = true;
                    obj.fs_div().css('display','block');
                    obj.fs_mousefollow(total_lines);
                    obj.prev_value = tval;
                }
            }
        });
    },
    terms: function() {
        return $('#'+this.s_field).val();
    }
});