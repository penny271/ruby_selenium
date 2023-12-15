# 使い方: 下記のコマンドを terminalに入力し実行する ※ファイル名の最後に取得したい対象のクライアントのアカウント番号を入力する 例: xxx.rb 1000
# cd aoki; cd manage; cd lib; cd tasks; cd scraping; DISABLE_SPRING=1 RAILS_ENV=development rails runner lib/tasks/scraping/scr_selenium_common_get_pic_urls.rb アカウント番号

require 'selenium-webdriver'
require 'csv'
# require_relative '../../import_product.rb'

def get_csv_info_object

  case @account_id
  when 10020 # SPARK株式会社
    return {
      product_path_prefix: 'https://www.desertrose-online.com/shopdetail',
      product_url_column_name: '商品ページURL',
      css_selectors: ['.swiper-slide-active > img'],
    }

  when 10025 # RePuBrew合同会社
    return {
      product_path_prefix: 'https://www.repubrew.com',
      product_url_column_name: '商品URLコード',
      # 列名メイングループが BEER/定期購入 の場合 , 列名メイングループが BEER/定期購入 以外の場合
      css_selectors: ['.fs-c-productPlainImage > img', '.fs-c-productMainImage__image > img'],
    }


  # ¥ スクレイピングなしで直接マスタ登録できるお客様
  else
    raise "★★★★★★★★★★★★★  該当する会社が存在しません。 ★★★★★★★★★★★★★"
  end
end


def complete_product_url(row)
  case @account_id
  when 10020
    # Directly return the URL for account ID 10020
    row[get_csv_info_object[:product_url_column_name]]

  when 10025
    # Determine the partial URL based on the 'メイングループ' value for account ID 10025
    added_partial_url = case row["メイングループ"]
                        when "BEER/Repubrew"
                          "/c/beer/repubrew/"
                        when "BEER/Natural Roots Studio"
                          "/c/beer/nrs/"
                        when "BEER/定期購入"
                          "/c/beer/gr11/"
                        when "GOODS"
                          "/c/goods/"
                        else
                          "/NOT_REGISTERED_MAIN_GROUP/"
                        end

    # Construct and return the complete URL
    get_csv_info_object[:product_path_prefix] + added_partial_url + row[get_csv_info_object[:product_url_column_name]]

  else
    # Raise an exception for unsupported account IDs
    raise "★★★★★★  本クライアントは登録されていません。本ファイルを編集してください ★★★★★★"
  end
end

puts()
puts("★★★もらったcsvファイルを一度googleDriveにアップし、それをcsvファイルにしないとCSV::MalformedCSVError (Invalid byte sequence in UTF-8 in line 1.):が起きるため、そのようにしてtmpフォルダーに保存し、そのファイルを読み込むこと!!★★★")
puts()
puts("★★★ tempフォルダに保存するファイル名ルールは アカウントID_商品一覧.csv とすること ★★★")

@account_id = ARGV[0]&.to_i

puts("@account_id ::: #{@account_id}")

if @account_id.blank? || !(1..99999).cover?(@account_id)
  raise "★★★★★★ ターミナルの第一引数にto_be_read_csv_file_nameを入力してください ★★★★★★"
end

# ! ローカル用に修正 - DBにアクセスできないため
# @company_name = Account.find_by(id: @account_id)["company_name"]
# to_be_read_csv_file_name = "#{@company_name}_商品一覧.csv"

to_be_read_csv_file_name = "#{@account_id}_商品一覧.csv"

puts("アカウントID: #{@account_id}")
puts("to_be_read_csv_file_name: #{to_be_read_csv_file_name}")


# Hash to store the extracted image data
image_data = {}

# Set up an array to hold the @URLs
@urls = []

# Build the absolute path to the CSV file
# csv_file_path = File.join(__dir__, "/csv_files/#{to_be_read_csv_file_name}")
# - 直接ファイルを上書きするため読み込み場所を更新 20230911
csv_file_path =  "tmp/#{to_be_read_csv_file_name}"
# csv_file_path =  "/root/aoki/manage/tmp/#{to_be_read_csv_file_name}"

# Open the CSV file and iterate over its rows
CSV.foreach(csv_file_path, headers: true, encoding: 'UTF-8') do |row|
  # Add the value in the "商品ページURL" column to the array
  # @urls << row["商品ページURL"]
  # product_url = row["商品ページURL"]
  product_url = complete_product_url(row)
  # puts("product_url - #{product_url}")
  @urls << product_url
end

total_url_num = @urls.length

done_count = 0

# Initialize the Selenium driver
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--headless') # Optional argument for headless mode
options.add_argument('--no-sandbox')
options.add_argument('--disable-dev-shm-usage')
# Set the path to chromedriver
# ¥ Set the path to chromedriver chromedriverの保存場所を見に行く 20230802
service = Selenium::WebDriver::Service.chrome(path: "/root/chromedriver-linux64/chromedriver")

# driver = Selenium::WebDriver.for :chrome, options: options, service: service
driver = Selenium::WebDriver.for :chrome, options: options


begin
  @urls.each_with_index do |url, index|
    done_count += 1
    sleep_sec = rand(1.0..1.1)

    begin
      driver.navigate.to url
      sleep(sleep_sec)

      img_element = nil # Declare img_element outside the loop

      get_csv_info_object[:css_selectors].each do |css_selector|
        img_element = driver.find_element(css: css_selector)
        puts("img_element.inspect ::: #{img_element.inspect}")
        break if img_element # if the element is found, break from the css_selector loop
      end


      img_src = img_element&.attribute('src') || 'notFound'

      # Store the img_src in the hash against the URL
      # image_data[url] = img_src
      image_data[index] = img_src

    rescue StandardError => e
      img_src = e.message

      # image_data[index] = e.message
      image_data[index] = "Not found"
      puts("Error: #{e.message}. Proceeding to the next URL.")
      next
    end

    puts("##{index+1}/#{total_url_num}番目 | sleep: #{sleep_sec}秒 | url: #{url} | 画像url: #{img_src}")

  end

rescue StandardError => e
  puts "An unexpected error occurred: #{e.message}. Saving data gathered so far..."
ensure
  # Append the new data to the original CSV file
  updated_rows = []
  selective_product_url_rows = []

  # ¥ 読み込み元のcsvファイルに新しく取得した画像urlの列を作成し、データを入れ、オリジナルのファイルを更新(上書き)する 20230915
  CSV.foreach(csv_file_path, headers: true, encoding: 'UTF-8').each_with_index do |row, c_idx|
    row['Image Source URL'] = image_data[c_idx]

    # Conditionally add Selective Product URL
    if @account_id == 10025
      row['Selective Product URL'] = @urls[c_idx]
    end

    updated_rows << row
  end

  # - Writing the Updated Data Back to the File:
  # Write the updated data back to the CSV
  CSV.open(csv_file_path, 'w', encoding: 'UTF-8') do |csv|
    # Add header row with the new columns
    csv << updated_rows.first.headers

    # Write updated rows back to the CSV
    updated_rows.each do |row|
      csv << row
    end
  end

  puts("The original CSV file has been updated at: #{csv_file_path}")
  # Quit the driver after use
  driver.quit

  # ! 会社名が アルファベットで始まっているため、開発環境では、 import_productのファイル名検索の正規表現が
  # ! うまく働かず、エラーが出るため、下記はコメントアウトしている
  # imp = ImportProduct.new(controller_name = '', @account_id = '', file_data = '' )
  # imp.import_product(controller_name = '', @account_id = 10020, file_data = '' )
end
